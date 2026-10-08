from django.contrib import admin, messages
from django.contrib.auth.admin import UserAdmin
from django import forms
from django.db import transaction
from rest_framework.exceptions import APIException
from .models import User, Store, Product, Order, OrderLine, Event, Report
from .services import transition


@admin.register(User)
class SellerAdmin(UserAdmin):
    ordering = ['email']
    list_display = ['email', 'name', 'is_active', 'is_staff']
    fieldsets = ((None, {'fields': ('email', 'name', 'password', 'is_active', 'is_staff', 'is_superuser', 'groups', 'user_permissions')}),)
    add_fieldsets = ((None, {'fields': ('email', 'name', 'password1', 'password2')}),)
    search_fields = ['email', 'name']

    def save_model(self, request, obj, form, change):
        if change:
            old = User.objects.get(pk=obj.pk)
            if old.is_active != obj.is_active or old.password != obj.password:
                obj.session_version = old.session_version + 1
        super().save_model(request, obj, form, change)


@admin.register(Store)
class StoreAdmin(admin.ModelAdmin):
    list_display = ['name', 'slug', 'published', 'suspended']
    readonly_fields = [f.name for f in Store._meta.fields if f.name != 'suspended']

    def has_add_permission(self, request):
        return False

    def has_delete_permission(self, request, obj=None):
        return False

    def save_model(self, request, obj, form, change):
        with transaction.atomic():
            locked = Store.objects.select_for_update().get(pk=obj.pk)
            locked.suspended = obj.suspended
            locked.save(update_fields=['suspended'])


@admin.register(Product)
class ProductAdmin(admin.ModelAdmin):
    list_display = ['name', 'store', 'stock', 'moderated']
    readonly_fields = [f.name for f in Product._meta.fields if f.name != 'moderated']

    def has_add_permission(self, request):
        return False

    def has_delete_permission(self, request, obj=None):
        return False

    def save_model(self, request, obj, form, change):
        with transaction.atomic():
            Store.objects.select_for_update().get(pk=obj.store_id)
            Product.objects.filter(pk=obj.pk).update(moderated=obj.moderated)


class LineInline(admin.TabularInline):
    model = OrderLine
    extra = 0
    can_delete = False
    readonly_fields = ['product', 'name', 'unit_price', 'quantity', 'line_total']

    def has_add_permission(self, request, obj=None):
        return False


class OrderForm(forms.ModelForm):
    correction_reason = forms.CharField(required=False, help_text='Superuser only: explain a mistaken payment confirmation to reverse it.')

    class Meta:
        model = Order
        fields = []


@admin.register(Order)
class OrderAdmin(admin.ModelAdmin):
    form = OrderForm
    list_display = ['reference', 'store', 'status', 'payment', 'total']
    readonly_fields = [f.name for f in Order._meta.fields if f.name != 'tracking_token']
    exclude = ['tracking_token']
    inlines = [LineInline]
    actions = ['accept', 'prepare', 'deliver', 'cancel']

    def has_add_permission(self, request):
        return False

    def has_delete_permission(self, request, obj=None):
        return False

    def run_action(self, request, queryset, action):
        if not request.user.is_superuser:
            self.message_user(request, 'Superuser required.', messages.ERROR)
            return
        for order in queryset:
            try:
                transition(order.pk, request.user, action)
            except APIException as exc:
                self.message_user(request, str(exc.detail), messages.ERROR)

    @admin.action(description='Accept (checks and deducts stock)')
    def accept(self, request, queryset):
        self.run_action(request, queryset, 'ACCEPTED')

    @admin.action(description='Mark preparing')
    def prepare(self, request, queryset):
        self.run_action(request, queryset, 'PREPARING')

    @admin.action(description='Mark delivered (does not confirm payment)')
    def deliver(self, request, queryset):
        self.run_action(request, queryset, 'DELIVERED')

    @admin.action(description='Cancel (restores reserved stock)')
    def cancel(self, request, queryset):
        self.run_action(request, queryset, 'CANCELLED')

    def save_model(self, request, obj, form, change):
        reason = form.cleaned_data.get('correction_reason', '').strip()
        if reason:
            try:
                transition(obj.pk, request.user, 'CORRECT_PAYMENT', reason=reason)
            except APIException as exc:
                self.message_user(request, str(exc.detail), messages.ERROR)
        # Never save the ModelForm's stale order instance over service updates.


@admin.register(Event)
class EventAdmin(admin.ModelAdmin):
    readonly_fields = [f.name for f in Event._meta.fields]
    list_display = ['order', 'action', 'actor', 'created_at']

    def has_add_permission(self, request):
        return False

    def has_delete_permission(self, request, obj=None):
        return False


@admin.register(Report)
class ReportAdmin(admin.ModelAdmin):
    list_display = ['store', 'product', 'created_at', 'resolved']
    readonly_fields = ['store', 'product', 'reason', 'created_at']
