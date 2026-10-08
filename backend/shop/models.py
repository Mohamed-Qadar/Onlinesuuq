import secrets
from decimal import Decimal
from django.contrib.auth.models import AbstractUser, BaseUserManager
from django.db import models
from django.db.models.functions import Lower
from django.core.validators import MinValueValidator, RegexValidator
from django.utils.translation import gettext_lazy as _
from django.utils import timezone


def token():
    return secrets.token_urlsafe(32)


phone_validator = RegexValidator(r'^\+[1-9]\d{6,14}$', _('Use an international phone number, for example +252612345678.'))


class UserManager(BaseUserManager):
    use_in_migrations = True

    def create_user(self, email, password=None, **extra):
        user = self.model(email=email.strip().lower(), **extra)
        user.set_password(password)
        user.save(using=self._db)
        return user

    def create_superuser(self, email, password, **extra):
        extra.update(is_staff=True, is_superuser=True)
        return self.create_user(email, password, **extra)


class User(AbstractUser):
    username = None
    email = models.EmailField(unique=True)
    name = models.CharField(max_length=120)
    session_version = models.PositiveIntegerField(default=1)
    USERNAME_FIELD = 'email'
    REQUIRED_FIELDS = ['name']
    objects = UserManager()

    class Meta:
        constraints = [models.UniqueConstraint(Lower('email'), name='email_case_insensitive')]

    def save(self, *args, **kwargs):
        self.email = self.email.strip().lower()
        super().save(*args, **kwargs)


class Store(models.Model):
    owner = models.OneToOneField(User, on_delete=models.PROTECT, related_name='store')
    name = models.CharField(max_length=120)
    slug = models.SlugField(unique=True)
    description = models.CharField(max_length=500, blank=True)
    logo = models.ImageField(upload_to='logos/', blank=True)
    phone = models.CharField(max_length=16, validators=[phone_validator])
    whatsapp = models.CharField(max_length=16, blank=True, validators=[phone_validator])
    city = models.CharField(max_length=100)
    delivery_regions = models.JSONField(default=list)
    pickup_instructions = models.CharField(max_length=300)
    delivery_fee = models.DecimalField(max_digits=10, decimal_places=2, default=0, validators=[MinValueValidator(0)])
    payment_provider = models.CharField(max_length=20, choices=[(n, n) for n in ['EVC Plus', 'eDahab', 'ZAAD', 'SAHAL', 'Other']])
    payment_account = models.CharField(max_length=100)
    payment_name = models.CharField(max_length=120)
    published = models.BooleanField(default=False)
    suspended = models.BooleanField(default=False)

    class Meta:
        constraints = [models.CheckConstraint(condition=models.Q(delivery_fee__gte=0), name='fee_nonnegative')]

    @property
    def available(self):
        return self.published and not self.suspended and self.owner.is_active


class Product(models.Model):
    store = models.ForeignKey(Store, on_delete=models.PROTECT, related_name='products')
    name = models.CharField(max_length=160)
    slug = models.SlugField()
    description = models.TextField(blank=True, max_length=4000)
    category = models.CharField(max_length=80, blank=True)
    price = models.DecimalField(max_digits=10, decimal_places=2, validators=[MinValueValidator(Decimal('0.01'))])
    stock = models.PositiveIntegerField(default=0)
    published = models.BooleanField(default=False)
    archived = models.BooleanField(default=False)
    moderated = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=['store', 'slug'], name='store_product_slug'),
            models.CheckConstraint(condition=models.Q(price__gt=0), name='price_positive'),
            models.CheckConstraint(condition=models.Q(stock__gte=0), name='stock_nonnegative')]


class Photo(models.Model):
    product = models.ForeignKey(Product, on_delete=models.CASCADE, related_name='photos')
    image = models.ImageField(upload_to='products/')


class GuestSession(models.Model):
    digest = models.CharField(max_length=64, unique=True)
    expires_at = models.DateTimeField()


class Order(models.Model):
    class Status(models.TextChoices):
        NEW = 'NEW', _('New')
        ACCEPTED = 'ACCEPTED', _('Accepted')
        PREPARING = 'PREPARING', _('Preparing')
        DELIVERED = 'DELIVERED', _('Delivered')
        CANCELLED = 'CANCELLED', _('Cancelled')

    class Payment(models.TextChoices):
        UNPAID = 'UNPAID', _('Unpaid')
        PAID = 'PAID', _('Paid — seller confirmed')
        REFUND_REQUIRED = 'REFUND_REQUIRED', _('Refund required')
        REFUNDED = 'REFUNDED', _('Refunded — seller confirmed')

    store = models.ForeignKey(Store, on_delete=models.PROTECT, related_name='orders')
    guest = models.ForeignKey(GuestSession, on_delete=models.PROTECT)
    idempotency_key = models.UUIDField()
    request_hash = models.CharField(max_length=64)
    tracking_token = models.CharField(max_length=64, unique=True, default=token, editable=False)
    reference = models.CharField(max_length=64, unique=True, default=token, editable=False)
    customer_name = models.CharField(max_length=120)
    phone = models.CharField(max_length=16, validators=[phone_validator])
    fulfillment = models.CharField(max_length=10, choices=[('pickup', _('Pickup')), ('delivery', _('Delivery'))])
    region = models.CharField(max_length=100, blank=True)
    address = models.CharField(max_length=500, blank=True)
    note = models.CharField(max_length=500, blank=True)
    delivery_fee = models.DecimalField(max_digits=10, decimal_places=2)
    total = models.DecimalField(max_digits=12, decimal_places=2)
    payment_instructions = models.JSONField()
    status = models.CharField(max_length=16, choices=Status.choices, default=Status.NEW)
    payment = models.CharField(max_length=20, choices=Payment.choices, default=Payment.UNPAID)
    payment_confirmed_by = models.ForeignKey(User, on_delete=models.PROTECT, null=True, related_name='+')
    payment_confirmed_at = models.DateTimeField(null=True)
    payment_reference = models.CharField(max_length=120, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=['guest', 'idempotency_key'], name='guest_idempotency')]


class OrderLine(models.Model):
    order = models.ForeignKey(Order, on_delete=models.PROTECT, related_name='lines')
    product = models.ForeignKey(Product, on_delete=models.PROTECT)
    name = models.CharField(max_length=160)
    unit_price = models.DecimalField(max_digits=10, decimal_places=2)
    quantity = models.PositiveIntegerField()
    line_total = models.DecimalField(max_digits=12, decimal_places=2)


class Event(models.Model):
    order = models.ForeignKey(Order, on_delete=models.PROTECT, related_name='events')
    actor = models.ForeignKey(User, on_delete=models.PROTECT, null=True)
    action = models.CharField(max_length=40)
    reason = models.CharField(max_length=500, blank=True)
    reference = models.CharField(max_length=120, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)


class Report(models.Model):
    store = models.ForeignKey(Store, on_delete=models.PROTECT)
    product = models.ForeignKey(Product, on_delete=models.PROTECT, null=True, blank=True)
    reason = models.CharField(max_length=1000)
    created_at = models.DateTimeField(auto_now_add=True)
    resolved = models.BooleanField(default=False)


class RateBucket(models.Model):
    key = models.CharField(max_length=64, unique=True)
    count = models.PositiveIntegerField(default=0)
    created_at = models.DateTimeField(default=timezone.now)
