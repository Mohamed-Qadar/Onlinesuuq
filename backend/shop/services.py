import hashlib
import json
from decimal import Decimal
from django.core import signing
from django.db import transaction
from django.utils import timezone
from django.utils.translation import gettext as _
from rest_framework.exceptions import ValidationError, PermissionDenied
from .models import Store, Product, Order, OrderLine, Event, GuestSession


def fail(message):
    raise ValidationError({'detail': message})


def sale_products():
    return Product.objects.filter(published=True, archived=False, moderated=False,
        store__published=True, store__suspended=False, store__owner__is_active=True)


def require_owner(store, actor):
    if not actor.is_active or (actor.pk != store.owner_id and not actor.is_superuser):
        raise PermissionDenied()


def quote_data(data, locked=False):
    store = Store.objects.get(pk=data['store'])
    if not store.available:
        fail(_('This store is unavailable.'))
    quantities = {line['product']: line['quantity'] for line in data['items']}
    if len(quantities) != len(data['items']):
        fail(_('Duplicate products are not allowed.'))
    products = sale_products().filter(store=store, pk__in=quantities).order_by('pk')
    if locked:
        products = products.select_for_update(of=('self',))
    products = list(products)
    if len(products) != len(quantities):
        fail(_('A product is unavailable.'))
    lines = []
    for product in products:
        qty = quantities[product.pk]
        if product.stock < qty:
            fail(_('Insufficient stock.'))
        lines.append({'product': product.pk, 'name': product.name, 'unit_price': str(product.price),
            'quantity': qty, 'line_total': str(product.price * qty)})
    fee = Decimal('0.00')
    if data['fulfillment'] == 'delivery':
        if data.get('region') not in store.delivery_regions or not data.get('address', '').strip():
            fail(_('Choose a delivery region and enter an address.'))
        fee = store.delivery_fee
    instructions = {'provider': store.payment_provider, 'account': store.payment_account, 'name': store.payment_name}
    total = sum((Decimal(x['line_total']) for x in lines), fee)
    if total > Decimal('9999999999.99'):
        fail(_('Order total exceeds the supported limit.'))
    return {'store': store.pk, 'lines': lines, 'delivery_fee': str(fee),
        'total': str(total),
        'payment_instructions': instructions}


def fingerprint(data):
    return hashlib.sha256(json.dumps(data, sort_keys=True, default=str).encode()).hexdigest()


def make_quote(guest, data):
    result = quote_data(data)
    return {k: v for k, v in result.items() if k != 'payment_instructions'} | {
        'quote': signing.dumps({'guest': guest.pk, 'data': fingerprint(data), 'quote': fingerprint(result)}, salt='checkout')}


@transaction.atomic
def checkout(guest, data, key, signed_quote):
    # Lock the anonymous session to serialize retries, even before an order exists.
    GuestSession.objects.select_for_update().get(pk=guest.pk)
    digest = fingerprint(data)
    existing = Order.objects.filter(guest=guest, idempotency_key=key).first()
    if existing:
        if existing.request_hash != digest:
            fail(_('This checkout key was already used for different details.'))
        return existing
    Store.objects.select_for_update().get(pk=data['store'])
    result = quote_data(data, locked=True)
    try:
        confirmed = signing.loads(signed_quote, salt='checkout', max_age=900)
    except signing.BadSignature:
        fail(_('Review the latest total and confirm again.'))
    if confirmed != {'guest': guest.pk, 'data': digest, 'quote': fingerprint(result)}:
        fail(_('Prices or order details changed. Review the latest total and confirm again.'))
    order = Order.objects.create(store_id=data['store'], guest=guest, idempotency_key=key, request_hash=digest,
        customer_name=data['customer_name'], phone=data['phone'], fulfillment=data['fulfillment'],
        region=data.get('region', ''), address=data.get('address', ''), note=data.get('note', ''),
        delivery_fee=result['delivery_fee'], total=result['total'], payment_instructions=result['payment_instructions'])
    for line in result['lines']:
        OrderLine.objects.create(order=order, product_id=line['product'], name=line['name'],
            unit_price=line['unit_price'], quantity=line['quantity'], line_total=line['line_total'])
    Event.objects.create(order=order, action='NEW')
    return order


@transaction.atomic
def transition(order_id, actor, action, *, confirmed=False, reference='', reason=''):
    # Global ordering: store -> order -> product IDs. Product editing uses the same store lock.
    store_id = Order.objects.values_list('store_id', flat=True).get(pk=order_id)
    store = Store.objects.select_for_update().get(pk=store_id)
    require_owner(store, actor)
    order = Order.objects.select_for_update().get(pk=order_id)
    previous_status, previous_payment = order.status, order.payment
    if action in Order.Status.values:
        if action == order.status:
            return order
        allowed = {'NEW': ['ACCEPTED', 'CANCELLED'], 'ACCEPTED': ['PREPARING', 'CANCELLED'],
            'PREPARING': ['DELIVERED', 'CANCELLED']}
        if action not in allowed.get(order.status, []):
            fail(_('Invalid order transition.'))
        if action == 'ACCEPTED':
            if not store.available:
                fail(_('This store is unavailable.'))
            lines = list(order.lines.order_by('product_id'))
            products = {p.pk: p for p in Product.objects.select_for_update().filter(
                pk__in=[line.product_id for line in lines]).order_by('pk')}
            for line in lines:
                p = products[line.product_id]
                if p.stock < line.quantity or p.archived or p.moderated or not p.published:
                    fail(_('Insufficient stock or unavailable product.'))
            for line in lines:
                p = products[line.product_id]
                p.stock -= line.quantity
                p.save(update_fields=['stock', 'updated_at'])
        if action == 'CANCELLED':
            if order.status in ['ACCEPTED', 'PREPARING']:
                for line in order.lines.order_by('product_id'):
                    product = Product.objects.select_for_update().get(pk=line.product_id)
                    product.stock += line.quantity
                    product.save(update_fields=['stock', 'updated_at'])
            if order.payment == 'PAID':
                order.payment = 'REFUND_REQUIRED'
        order.status = action
    elif action in ['PAID', 'REFUNDED']:
        if not confirmed:
            fail(_('Explicit confirmation is required.'))
        if action == 'PAID' and (order.status not in ['ACCEPTED', 'PREPARING', 'DELIVERED'] or order.payment != 'UNPAID'):
            fail(_('Payment cannot be confirmed for this order.'))
        if action == 'REFUNDED' and (order.status != 'CANCELLED' or order.payment != 'REFUND_REQUIRED'):
            fail(_('No refund is awaiting confirmation.'))
        order.payment = action
        order.payment_confirmed_by = actor
        order.payment_confirmed_at = timezone.now()
        order.payment_reference = reference
    elif action == 'CORRECT_PAYMENT':
        if not actor.is_superuser or not reason.strip() or order.payment not in ['PAID', 'REFUND_REQUIRED']:
            raise PermissionDenied(_('Only an administrator may correct a payment, with a reason.'))
        order.payment = 'UNPAID'
    else:
        fail(_('Invalid order transition.'))
    order.save()
    Event.objects.create(order=order, actor=actor, action=action,
        reference=reference,
        reason=f'{previous_status}/{previous_payment} -> {order.status}/{order.payment}. {reason}'.strip())
    return order


@transaction.atomic
def publish_store(store_id, actor, published):
    store = Store.objects.select_for_update().get(pk=store_id)
    require_owner(store, actor)
    if published:
        if store.suspended or not all([store.phone, store.city, store.pickup_instructions,
                store.payment_account, store.payment_name, store.payment_provider]):
            fail(_('Complete your store profile before publishing.'))
        if not store.products.filter(published=True, archived=False, moderated=False, stock__gt=0).exists():
            fail(_('Add an available published product first.'))
    store.published = published
    store.save(update_fields=['published'])
    return store
