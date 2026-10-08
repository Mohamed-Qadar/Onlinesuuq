import hashlib
import secrets
from datetime import timedelta
from django.conf import settings
from django.contrib.auth.password_validation import validate_password
from django.contrib.auth.tokens import default_token_generator
from django.core.mail import send_mail
from django.db import transaction, IntegrityError
from django.db.models import Q, Sum
from django.shortcuts import get_object_or_404
from django.utils import timezone
from django.utils.encoding import force_bytes, force_str
from django.utils.http import urlsafe_base64_encode, urlsafe_base64_decode
from django.utils.translation import gettext as _
from rest_framework import generics, viewsets, serializers
from rest_framework.decorators import action
from rest_framework.exceptions import AuthenticationFailed, ValidationError
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.exceptions import TokenError
from drf_spectacular.utils import extend_schema, inline_serializer, OpenApiParameter
from .models import User, Store, Product, Photo, GuestSession, Order
from .serializers import (RegisterSerializer, StoreSerializer, PublicStoreSerializer, ProductSerializer,
    OrderSerializer, TrackingSerializer, CheckoutSerializer, SubmitSerializer, ActionSerializer, ReportSerializer,
    QuoteResultSerializer, CheckoutResultSerializer)
from .services import make_quote, checkout, transition, publish_store, sale_products
from .security import rate_limit, clean_image


class RegisterView(generics.CreateAPIView):
    authentication_classes = []
    permission_classes = [AllowAny]
    serializer_class = RegisterSerializer

    def create(self, request, *args, **kwargs):
        rate_limit(request, 'register', 10)
        try:
            return super().create(request, *args, **kwargs)
        except IntegrityError:
            raise ValidationError(_('This email is already registered.'))


class LoginView(TokenObtainPairView):
    def post(self, request, *args, **kwargs):
        rate_limit(request, 'login', 30)
        return super().post(request, *args, **kwargs)


class RefreshView(TokenRefreshView):
    def post(self, request, *args, **kwargs):
        rate_limit(request, 'refresh', 180)
        return super().post(request, *args, **kwargs)


class LogoutView(APIView):
    @extend_schema(request=inline_serializer('Logout', {'refresh': serializers.CharField()}), responses={204: None})
    def post(self, request):
        with transaction.atomic():
            user = User.objects.select_for_update().get(pk=request.user.pk)
            try:
                token = RefreshToken(request.data.get('refresh', ''))
                if int(token['user_id']) != user.pk:
                    raise AuthenticationFailed()
                token.blacklist()
            except TokenError:
                pass
            user.session_version += 1  # Also invalidate outstanding access tokens.
            user.save(update_fields=['session_version'])
        return Response(status=204)


class PasswordView(APIView):
    @extend_schema(request=inline_serializer('PasswordChange', {'old_password': serializers.CharField(), 'password': serializers.CharField()}), responses={204: None})
    def post(self, request):
        rate_limit(request, 'password', 20)
        with transaction.atomic():
            user = User.objects.select_for_update().get(pk=request.user.pk)
            if not user.check_password(request.data.get('old_password', '')):
                raise ValidationError(_('Current password is incorrect.'))
            new = request.data.get('password', '')
            try:
                validate_password(new, user)
            except Exception as exc:
                raise ValidationError(getattr(exc, 'messages', [str(exc)]))
            user.set_password(new)
            user.session_version += 1
            user.save()
        return Response(status=204)


class ResetView(APIView):
    authentication_classes = []
    permission_classes = [AllowAny]

    @extend_schema(request=inline_serializer('ResetRequest', {'email': serializers.EmailField()}), responses={204: None})
    def post(self, request):
        rate_limit(request, 'reset', 5)
        email = str(request.data.get('email', '')).strip().lower()
        user = User.objects.filter(email=email, is_active=True).first()
        if user:
            uid = urlsafe_base64_encode(force_bytes(user.pk))
            token = default_token_generator.make_token(user)
            send_mail(settings.BRAND_NAME + ' — Password reset',
                f'Enter these values in the app password reset screen.\nUser code: {uid}\nReset code: {token}',
                settings.DEFAULT_FROM_EMAIL, [user.email])
        return Response(status=204)


class ResetConfirmView(APIView):
    authentication_classes = []
    permission_classes = [AllowAny]

    @extend_schema(request=inline_serializer('ResetConfirm', {'uid': serializers.CharField(), 'token': serializers.CharField(), 'password': serializers.CharField()}), responses={204: None})
    def post(self, request):
        rate_limit(request, 'reset-confirm', 20)
        try:
            pk = force_str(urlsafe_base64_decode(request.data.get('uid', '')))
            with transaction.atomic():
                user = User.objects.select_for_update().get(pk=pk, is_active=True)
                if not default_token_generator.check_token(user, request.data.get('token', '')):
                    raise ValueError()
                validate_password(request.data.get('password', ''), user)
                user.set_password(request.data['password'])
                user.session_version += 1
                user.save()
        except Exception:
            raise ValidationError(_('Invalid reset code or password.'))
        return Response(status=204)


class PublicStores(viewsets.ReadOnlyModelViewSet):
    authentication_classes = []
    permission_classes = [AllowAny]
    serializer_class = PublicStoreSerializer
    lookup_field = 'slug'

    def get_queryset(self):
        qs = Store.objects.filter(published=True, suspended=False, owner__is_active=True).order_by('name')
        if self.action == 'list':
            query = self.request.query_params.get('q', '').strip()
            return qs.filter(Q(slug__iexact=query) | Q(name__icontains=query)) if query else qs.none()
        return qs

    @action(detail=True, serializer_class=ProductSerializer)
    def products(self, request, slug=None):
        qs = sale_products().filter(store=self.get_object()).prefetch_related('photos').order_by('name')
        if request.query_params.get('q'):
            qs = qs.filter(name__icontains=request.query_params['q'])
        if request.query_params.get('category'):
            qs = qs.filter(category=request.query_params['category'])
        return self.get_paginated_response(ProductSerializer(self.paginate_queryset(qs), many=True, context={'request': request}).data)


class PublicProduct(generics.RetrieveAPIView):
    authentication_classes = []
    permission_classes = [AllowAny]
    serializer_class = ProductSerializer
    queryset = sale_products().prefetch_related('photos')


class MyStore(generics.GenericAPIView):
    serializer_class = StoreSerializer

    def get(self, request):
        return Response(self.get_serializer(get_object_or_404(Store, owner=request.user)).data)

    def post(self, request):
        ser = self.get_serializer(data=request.data)
        ser.is_valid(raise_exception=True)
        try:
            with transaction.atomic():
                User.objects.select_for_update().get(pk=request.user.pk)
                if Store.objects.filter(owner=request.user).exists():
                    raise ValidationError(_('You already have a store.'))
                ser.save(owner=request.user)
        except IntegrityError:
            raise ValidationError(_('This store code is already used.'))
        return Response(ser.data, status=201)

    def patch(self, request):
        try:
            with transaction.atomic():
                store = get_object_or_404(Store.objects.select_for_update(), owner=request.user)
                ser = self.get_serializer(store, data=request.data, partial=True)
                ser.is_valid(raise_exception=True)
                ser.save()
        except IntegrityError:
            raise ValidationError(_('This store code is already used.'))
        return Response(ser.data)


class PublishView(APIView):
    @extend_schema(request=inline_serializer('Publish', {'published': serializers.BooleanField()}), responses=StoreSerializer)
    def post(self, request):
        ser = inline_serializer('PublishInput', {'published': serializers.BooleanField()}, data=request.data)
        ser.is_valid(raise_exception=True)
        store = get_object_or_404(Store, owner=request.user)
        store = publish_store(store.pk, request.user, ser.validated_data['published'])
        return Response(StoreSerializer(store, context={'request': request}).data)


class LogoView(APIView):
    @extend_schema(request=inline_serializer('LogoUpload', {'image': serializers.ImageField()}), responses=StoreSerializer)
    def post(self, request):
        image = request.FILES.get('image')
        if image is None:
            raise ValidationError(_('Choose an image.'))
        image = clean_image(image)
        with transaction.atomic():
            store = get_object_or_404(Store.objects.select_for_update(), owner=request.user)
            store.logo.save(image.name, image)
        return Response(StoreSerializer(store, context={'request': request}).data)


class MyProducts(viewsets.ModelViewSet):
    serializer_class = ProductSerializer
    http_method_names = ['get', 'post', 'patch', 'head', 'options', 'delete']

    def get_queryset(self):
        if getattr(self, 'swagger_fake_view', False):
            return Product.objects.none()
        return Product.objects.filter(store__owner=self.request.user).prefetch_related('photos').order_by('-created_at')

    def create(self, request, *args, **kwargs):
        try:
            return super().create(request, *args, **kwargs)
        except IntegrityError:
            raise ValidationError(_('This product code is already used.'))

    def perform_create(self, serializer):
        with transaction.atomic():
            store = get_object_or_404(Store.objects.select_for_update(), owner=self.request.user)
            serializer.save(store=store)

    def update(self, request, *args, **kwargs):
        try:
            with transaction.atomic():
                get_object_or_404(Store.objects.select_for_update(), owner=request.user)
                # Version check and object read are both inside the lock.
                return super().update(request, *args, **kwargs)
        except IntegrityError:
            raise ValidationError(_('This product code is already used.'))

    def perform_destroy(self, instance):
        with transaction.atomic():
            Store.objects.select_for_update().get(pk=instance.store_id)
            Product.objects.filter(pk=instance.pk).update(archived=True, published=False)

    @extend_schema(request=inline_serializer('PhotoUpload', {'image': serializers.ImageField()}), responses=ProductSerializer)
    @action(detail=True, methods=['post'])
    def photos(self, request, pk=None):
        with transaction.atomic():
            get_object_or_404(Store.objects.select_for_update(), owner=request.user)
            product = self.get_object()
            if product.photos.count() >= 3:
                raise ValidationError(_('A product can have at most three photos.'))
            image = request.FILES.get('image')
            if image is None:
                raise ValidationError(_('Choose an image.'))
            image = clean_image(image)
            Photo.objects.create(product=product, image=image)
        return Response(self.get_serializer(product).data)

    @action(detail=True, methods=['delete'], url_path=r'photos/(?P<photo_id>\d+)')
    def remove_photo(self, request, pk=None, photo_id=None):
        with transaction.atomic():
            get_object_or_404(Store.objects.select_for_update(), owner=request.user)
            photo = get_object_or_404(Photo, product=self.get_object(), pk=photo_id)
            photo.delete()
        return Response(status=204)


class MyOrders(viewsets.ReadOnlyModelViewSet):
    serializer_class = OrderSerializer

    def get_queryset(self):
        if getattr(self, 'swagger_fake_view', False):
            return Order.objects.none()
        qs = Order.objects.filter(store__owner=self.request.user).prefetch_related('lines', 'events').order_by('-created_at')
        status = self.request.query_params.get('status')
        if status:
            qs = qs.filter(status=status)
        for param, lookup in [('from', 'created_at__date__gte'), ('to', 'created_at__date__lte')]:
            if self.request.query_params.get(param):
                field = serializers.DateField()
                qs = qs.filter(**{lookup: field.run_validation(self.request.query_params[param])})
        return qs

    @extend_schema(request=ActionSerializer, responses=OrderSerializer)
    @action(detail=True, methods=['post'])
    def act(self, request, pk=None):
        order = self.get_object()
        ser = ActionSerializer(data=request.data)
        ser.is_valid(raise_exception=True)
        order = transition(order.pk, request.user, **ser.validated_data)
        return Response(self.get_serializer(order).data)


class Dashboard(APIView):
    @extend_schema(responses=inline_serializer('DashboardResult', {
        'active_products': serializers.IntegerField(), 'new_orders': serializers.IntegerField(),
        'preparing_orders': serializers.IntegerField(), 'seller_confirmed_total': serializers.DecimalField(max_digits=14, decimal_places=2),
        'low_stock': ProductSerializer(many=True)}))
    def get(self, request):
        store = get_object_or_404(Store, owner=request.user)
        return Response({'active_products': store.products.filter(published=True, archived=False, moderated=False).count(),
            'new_orders': store.orders.filter(status='NEW').count(), 'preparing_orders': store.orders.filter(status='PREPARING').count(),
            'seller_confirmed_total': str(store.orders.filter(payment='PAID').exclude(status='CANCELLED').aggregate(n=Sum('total'))['n'] or '0.00'),
            'low_stock': ProductSerializer(store.products.filter(stock__lte=3, archived=False)[:20], many=True, context={'request': request}).data})


def get_guest(request, *, allow_expired_result=False):
    raw = request.headers.get('X-Guest-Token', '')
    if not raw or len(raw) > 100:
        raise AuthenticationFailed(_('Guest session expired.'))
    digest = hashlib.sha256(raw.encode()).hexdigest()
    sessions = GuestSession.objects.filter(digest=digest)
    if not allow_expired_result:
        sessions = sessions.filter(expires_at__gt=timezone.now())
    guest = sessions.first()
    if not guest:
        raise AuthenticationFailed(_('Guest session expired.'))
    return guest


class GuestView(APIView):
    authentication_classes = []
    permission_classes = [AllowAny]

    @extend_schema(request=None, responses=inline_serializer('GuestSessionResult', {'token': serializers.CharField(), 'expires_at': serializers.DateTimeField()}))
    def post(self, request):
        rate_limit(request, 'guest', 30)
        raw = secrets.token_urlsafe(32)
        guest = GuestSession.objects.create(digest=hashlib.sha256(raw.encode()).hexdigest(), expires_at=timezone.now() + timedelta(days=30))
        return Response({'token': raw, 'expires_at': guest.expires_at}, status=201)


class QuoteView(generics.GenericAPIView):
    authentication_classes = []
    permission_classes = [AllowAny]
    serializer_class = CheckoutSerializer

    @extend_schema(responses=QuoteResultSerializer, parameters=[OpenApiParameter('X-Guest-Token', str, OpenApiParameter.HEADER, required=True)])
    def post(self, request):
        rate_limit(request, 'quote', 120)
        guest = get_guest(request)
        ser = self.get_serializer(data=request.data)
        ser.is_valid(raise_exception=True)
        return Response(make_quote(guest, ser.validated_data))


class CheckoutView(QuoteView):
    serializer_class = SubmitSerializer

    @extend_schema(responses={201: CheckoutResultSerializer}, parameters=[OpenApiParameter('X-Guest-Token', str, OpenApiParameter.HEADER, required=True)])
    def post(self, request):
        rate_limit(request, 'checkout', 60)
        guest = get_guest(request)
        ser = self.get_serializer(data=request.data)
        ser.is_valid(raise_exception=True)
        data = dict(ser.validated_data)
        key, quote = data.pop('idempotency_key'), data.pop('quote')
        order = checkout(guest, data, key, quote)
        return Response({'tracking_token': order.tracking_token, 'order': TrackingSerializer(order).data}, status=201)


class CheckoutResult(APIView):
    authentication_classes = []
    permission_classes = [AllowAny]

    @extend_schema(responses=CheckoutResultSerializer, parameters=[OpenApiParameter('X-Guest-Token', str, OpenApiParameter.HEADER, required=True)])
    def get(self, request, key):
        rate_limit(request, 'result', 180)
        # An expired token can only recover its own already-created result, not submit.
        order = get_object_or_404(Order, guest=get_guest(request, allow_expired_result=True), idempotency_key=key)
        return Response({'tracking_token': order.tracking_token, 'order': TrackingSerializer(order).data})


class Tracking(APIView):
    authentication_classes = []
    permission_classes = [AllowAny]

    @extend_schema(responses=TrackingSerializer, parameters=[OpenApiParameter('X-Tracking-Token', str, OpenApiParameter.HEADER, required=True)])
    def get(self, request):
        rate_limit(request, 'tracking', 180)
        order = get_object_or_404(Order, tracking_token=request.headers.get('X-Tracking-Token', ''))
        return Response(TrackingSerializer(order).data)


class ReportView(generics.CreateAPIView):
    authentication_classes = []
    permission_classes = [AllowAny]
    serializer_class = ReportSerializer

    def create(self, request, *args, **kwargs):
        rate_limit(request, 'report', 10)
        return super().create(request, *args, **kwargs)


class Configuration(APIView):
    permission_classes = [AllowAny]
    authentication_classes = []

    @extend_schema(responses=inline_serializer('ConfigurationResult', {
        'brand_name': serializers.CharField(), 'publisher_name': serializers.CharField(),
        'privacy_url': serializers.CharField(), 'account_deletion_url': serializers.CharField()}))
    def get(self, request):
        return Response({'brand_name': settings.BRAND_NAME, 'publisher_name': settings.PUBLISHER_NAME,
            'privacy_url': request.build_absolute_uri('/privacy/'),
            'account_deletion_url': request.build_absolute_uri('/account-deletion/')})


class DeleteAccountView(APIView):
    # Permanent account deletion, required by Google Play. Personal identifiers are
    # scrubbed and the account is deactivated. Existing order/audit records are kept
    # (they carry no live contact details), as disclosed on the account-deletion page.
    @extend_schema(request=inline_serializer('AccountDelete', {'password': serializers.CharField()}), responses={204: None})
    def post(self, request):
        rate_limit(request, 'delete-account', 20)
        with transaction.atomic():
            user = User.objects.select_for_update().get(pk=request.user.pk)
            if not user.check_password(request.data.get('password', '')):
                raise ValidationError(_('Current password is incorrect.'))
            store = Store.objects.select_for_update().filter(owner=user).first()
            if store:
                for photo in Photo.objects.filter(product__store=store):
                    photo.image.delete(save=False)
                    photo.delete()
                store.products.update(published=False, archived=True)
                if store.logo:
                    store.logo.delete(save=False)
                # Hide the shop and remove the owner's contact and payment identifiers.
                store.published = False
                store.phone = store.whatsapp = ''
                store.description = ''
                store.payment_account = store.payment_name = ''
                store.save()
            user.email = f'deleted-{user.pk}@deleted.invalid'
            user.name = str(_('Deleted account'))
            user.set_unusable_password()
            user.is_active = False
            user.session_version += 1  # Invalidate outstanding access and refresh tokens.
            user.save()
        return Response(status=204)
