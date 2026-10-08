from django.contrib.auth.password_validation import validate_password
from django.utils.translation import gettext_lazy as _
from django.shortcuts import get_object_or_404
from rest_framework import serializers
from drf_spectacular.utils import extend_schema_field
from .models import User, Store, Product, Photo, Order, OrderLine, Event, Report, phone_validator


class RegisterSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True)
    password_repeat = serializers.CharField(write_only=True)

    class Meta:
        model = User
        fields = ['id', 'name', 'email', 'password', 'password_repeat']
        read_only_fields = ['id']

    def validate(self, attrs):
        attrs['email'] = attrs['email'].strip().lower()
        if User.objects.filter(email__iexact=attrs['email']).exists():
            raise serializers.ValidationError(_('This email is already registered.'))
        if attrs['password'] != attrs.pop('password_repeat'):
            raise serializers.ValidationError(_('Passwords do not match.'))
        validate_password(attrs['password'], User(email=attrs['email'], name=attrs['name']))
        return attrs

    def create(self, validated_data):
        return User.objects.create_user(**validated_data)


class StoreSerializer(serializers.ModelSerializer):
    class Meta:
        model = Store
        fields = ['id', 'name', 'slug', 'description', 'logo', 'phone', 'whatsapp', 'city', 'delivery_regions',
            'pickup_instructions', 'delivery_fee', 'payment_provider', 'payment_account', 'payment_name', 'published', 'suspended']
        read_only_fields = ['id', 'logo', 'published', 'suspended']

    def validate_delivery_regions(self, value):
        if not isinstance(value, list) or len(value) > 50 or any(not isinstance(s, str) or not s.strip() or len(s) > 100 for s in value):
            raise serializers.ValidationError(_('Enter a list of delivery regions.'))
        return list(dict.fromkeys(s.strip() for s in value))

    def validate_slug(self, value):
        return value.lower()


class PublicStoreSerializer(StoreSerializer):
    class Meta(StoreSerializer.Meta):
        fields = [f for f in StoreSerializer.Meta.fields if f not in ['payment_provider', 'payment_account', 'payment_name', 'suspended']]


class PhotoSerializer(serializers.ModelSerializer):
    class Meta:
        model = Photo
        fields = ['id', 'image']


class ProductSerializer(serializers.ModelSerializer):
    photos = PhotoSerializer(many=True, read_only=True)
    expected_updated_at = serializers.DateTimeField(write_only=True, required=False)

    class Meta:
        model = Product
        fields = ['id', 'store', 'name', 'slug', 'description', 'category', 'price', 'stock',
            'published', 'archived', 'moderated', 'photos', 'created_at', 'updated_at', 'expected_updated_at']
        read_only_fields = ['id', 'store', 'moderated', 'photos', 'created_at', 'updated_at']
        validators = []

    def validate(self, attrs):
        store = get_object_or_404(Store, owner=self.context['request'].user)
        expected = attrs.pop('expected_updated_at', None)
        if self.instance and 'stock' in attrs and expected != self.instance.updated_at:
            raise serializers.ValidationError(_('Stock changed or needs a fresh version. Reload the product before editing.'))
        slug = attrs.get('slug', self.instance.slug if self.instance else '')
        qs = Product.objects.filter(store=store, slug=slug)
        if self.instance:
            qs = qs.exclude(pk=self.instance.pk)
        if qs.exists():
            raise serializers.ValidationError(_('This product code is already used.'))
        return attrs


class LineSerializer(serializers.ModelSerializer):
    class Meta:
        model = OrderLine
        fields = ['name', 'unit_price', 'quantity', 'line_total']


class EventSerializer(serializers.ModelSerializer):
    class Meta:
        model = Event
        fields = ['action', 'reason', 'reference', 'created_at', 'actor']


class OrderSerializer(serializers.ModelSerializer):
    lines = LineSerializer(many=True, read_only=True)
    events = EventSerializer(many=True, read_only=True)

    class Meta:
        model = Order
        fields = ['id', 'reference', 'customer_name', 'phone', 'fulfillment', 'region', 'address', 'note',
            'delivery_fee', 'total', 'status', 'payment', 'payment_instructions', 'payment_confirmed_at',
            'payment_confirmed_by', 'payment_reference', 'lines', 'events', 'created_at']
        read_only_fields = fields


class TrackingSerializer(serializers.ModelSerializer):
    lines = LineSerializer(many=True, read_only=True)
    payment_instructions = serializers.SerializerMethodField()

    @extend_schema_field(serializers.DictField(child=serializers.CharField(), allow_null=True))
    def get_payment_instructions(self, order):
        return order.payment_instructions if order.status in ['ACCEPTED', 'PREPARING', 'DELIVERED'] else None

    class Meta:
        model = Order
        fields = ['reference', 'status', 'payment', 'fulfillment', 'delivery_fee', 'total', 'lines', 'payment_instructions', 'created_at']


class CheckoutLineSerializer(serializers.Serializer):
    product = serializers.IntegerField(min_value=1)
    quantity = serializers.IntegerField(min_value=1, max_value=999)


class CheckoutSerializer(serializers.Serializer):
    store = serializers.PrimaryKeyRelatedField(queryset=Store.objects.all(), pk_field=serializers.IntegerField())
    items = CheckoutLineSerializer(many=True, allow_empty=False, max_length=50)
    customer_name = serializers.CharField(max_length=120)
    phone = serializers.CharField(max_length=16, validators=[phone_validator])
    fulfillment = serializers.ChoiceField(choices=Order._meta.get_field('fulfillment').choices)
    region = serializers.CharField(max_length=100, required=False, allow_blank=True, default='')
    address = serializers.CharField(max_length=500, required=False, allow_blank=True, default='')
    note = serializers.CharField(max_length=500, required=False, allow_blank=True, default='')

    def validate_store(self, value):
        return value.pk


class SubmitSerializer(CheckoutSerializer):
    idempotency_key = serializers.UUIDField()
    quote = serializers.CharField()


class ActionSerializer(serializers.Serializer):
    action = serializers.ChoiceField(choices=['ACCEPTED', 'PREPARING', 'DELIVERED', 'CANCELLED', 'PAID', 'REFUNDED', 'CORRECT_PAYMENT'])
    confirmed = serializers.BooleanField(default=False)
    reference = serializers.CharField(max_length=120, required=False, allow_blank=True, default='')
    reason = serializers.CharField(max_length=300, required=False, allow_blank=True, default='')


class ReportSerializer(serializers.ModelSerializer):
    class Meta:
        model = Report
        fields = ['store', 'product', 'reason']

    def validate(self, attrs):
        if attrs.get('product') and attrs['product'].store_id != attrs['store'].pk:
            raise serializers.ValidationError(_('The product must belong to this store.'))
        return attrs


class QuoteLineSerializer(serializers.Serializer):
    product = serializers.IntegerField()
    name = serializers.CharField()
    unit_price = serializers.DecimalField(max_digits=10, decimal_places=2)
    quantity = serializers.IntegerField()
    line_total = serializers.DecimalField(max_digits=12, decimal_places=2)


class QuoteResultSerializer(serializers.Serializer):
    store = serializers.IntegerField()
    lines = QuoteLineSerializer(many=True)
    delivery_fee = serializers.DecimalField(max_digits=10, decimal_places=2)
    total = serializers.DecimalField(max_digits=12, decimal_places=2)
    quote = serializers.CharField()


class CheckoutResultSerializer(serializers.Serializer):
    tracking_token = serializers.CharField()
    order = TrackingSerializer()
