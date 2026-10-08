import hashlib
import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta
from io import BytesIO
from threading import Barrier
from PIL import Image
from django.contrib.admin.sites import AdminSite
from django.core.files.uploadedfile import SimpleUploadedFile
from django.db import close_old_connections, connection
from django.test import TestCase, TransactionTestCase, override_settings
from django.utils import timezone
from rest_framework.test import APIClient
from rest_framework.exceptions import ValidationError
from .models import User, Store, Product, GuestSession, Order, Event, RateBucket
from .services import make_quote, checkout, transition
from .admin import OrderAdmin, ProductAdmin


def fixture():
    user = User.objects.create_user('seller@example.invalid', 'Safe-long-pass-42!', name='Seller')
    other = User.objects.create_user('other@example.invalid', 'Safe-long-pass-42!', name='Other')
    store = Store.objects.create(owner=user, name='Demo', slug='demo', phone='+252612345678', city='Demo',
        pickup_instructions='Pickup', delivery_regions=['Zone A'], delivery_fee='2.50', payment_provider='Other',
        payment_account='TEST-ACCOUNT', payment_name='Demo', published=True)
    p = Product.objects.create(store=store, name='Tea', slug='tea', price='5.00', stock=5, published=True)
    guest = GuestSession.objects.create(digest=hashlib.sha256(b'guest-test').hexdigest(), expires_at=timezone.now()+timedelta(days=1))
    return user, other, store, p, guest


def data_for(store, product, qty=1):
    return {'store': store.pk, 'items': [{'product': product.pk, 'quantity': qty}], 'customer_name': 'Guest',
        'phone': '+252612345678', 'fulfillment': 'pickup', 'region': '', 'address': '', 'note': ''}


@override_settings(SECURE_SSL_REDIRECT=False, LANGUAGE_CODE='en', EMAIL_BACKEND='django.core.mail.backends.locmem.EmailBackend')
class APITests(TestCase):
    def setUp(self):
        self.user, self.other, self.store, self.product, self.guest = fixture()
        self.client = APIClient()
        self.client.credentials(HTTP_X_GUEST_TOKEN='guest-test', HTTP_ACCEPT_LANGUAGE='en')

    def order(self, qty=1):
        data = data_for(self.store, self.product, qty)
        return checkout(self.guest, data, uuid.uuid4(), make_quote(self.guest, data)['quote'])

    def seller(self, user=None):
        self.client.force_authenticate(user or self.user)

    def test_registration_login_refresh_logout(self):
        result = self.client.post('/api/v1/auth/register/', {'name': 'New', 'email': 'NEW@example.invalid',
            'password': 'Fresh-Strong-Password-46!', 'password_repeat': 'Fresh-Strong-Password-46!', 'is_staff': True}, format='json')
        self.assertEqual(result.status_code, 201, result.data)
        self.assertFalse(User.objects.get(email='new@example.invalid').is_staff)
        login = self.client.post('/api/v1/auth/login/', {'email': 'NEW@example.invalid', 'password': 'Fresh-Strong-Password-46!'}, format='json')
        self.assertEqual(login.status_code, 200)
        old_refresh = login.data['refresh']
        refreshed = self.client.post('/api/v1/auth/refresh/', {'refresh': old_refresh}, format='json')
        self.assertEqual(refreshed.status_code, 200)
        self.assertEqual(self.client.post('/api/v1/auth/refresh/', {'refresh': old_refresh}, format='json').status_code, 401)
        self.client.credentials(HTTP_AUTHORIZATION='Bearer '+refreshed.data['access'])
        self.assertEqual(self.client.post('/api/v1/auth/logout/', {'refresh': refreshed.data['refresh']}, format='json').status_code, 204)
        self.assertEqual(self.client.get('/api/v1/seller/store/').status_code, 401)

    def test_email_case_duplicate(self):
        r = self.client.post('/api/v1/auth/register/', {'name': 'Duplicate', 'email': 'SELLER@example.invalid',
            'password': 'Fresh-Strong-Password-46!', 'password_repeat': 'Fresh-Strong-Password-46!'}, format='json')
        self.assertEqual(r.status_code, 400)

    def test_password_change_invalidates_access_and_refresh(self):
        pair = self.client.post('/api/v1/auth/login/', {'email': self.user.email, 'password': 'Safe-long-pass-42!'}, format='json').data
        self.client.credentials(HTTP_AUTHORIZATION='Bearer '+pair['access'])
        self.assertEqual(self.client.post('/api/v1/auth/password/', {'old_password': 'Safe-long-pass-42!', 'password': 'New-secret-long-81!'}, format='json').status_code, 204)
        self.assertEqual(self.client.get('/api/v1/seller/store/').status_code, 401)
        self.assertEqual(self.client.post('/api/v1/auth/refresh/', {'refresh': pair['refresh']}, format='json').status_code, 401)

    def test_inactive_account_rejected(self):
        self.user.is_active = False
        self.user.save()
        r = self.client.post('/api/v1/auth/login/', {'email': self.user.email, 'password': 'Safe-long-pass-42!'}, format='json')
        self.assertEqual(r.status_code, 401)

    def test_password_reset(self):
        from django.core import mail
        from django.contrib.auth.tokens import default_token_generator
        from django.utils.http import urlsafe_base64_encode
        from django.utils.encoding import force_bytes
        self.assertEqual(self.client.post('/api/v1/auth/reset/', {'email': self.user.email}).status_code, 204)
        self.assertEqual(len(mail.outbox), 1)
        body = {'uid': urlsafe_base64_encode(force_bytes(self.user.pk)), 'token': default_token_generator.make_token(self.user), 'password': 'Changed-secret-43!'}
        self.assertEqual(self.client.post('/api/v1/auth/reset/confirm/', body).status_code, 204)
        self.assertEqual(self.client.post('/api/v1/auth/reset/confirm/', body).status_code, 400)

    def test_delete_account_wrong_password_rejected(self):
        self.seller()
        r = self.client.post('/api/v1/auth/delete/', {'password': 'wrong-password'}, format='json')
        self.assertEqual(r.status_code, 400)
        self.user.refresh_from_db()
        self.assertTrue(self.user.is_active)

    def test_delete_account_scrubs_and_deactivates(self):
        order = self.order()  # An order referencing the seller's store must survive deletion.
        self.product.photos.create(image=SimpleUploadedFile('p.jpg', b'x', content_type='image/jpeg'))
        pair = self.client.post('/api/v1/auth/login/', {'email': self.user.email, 'password': 'Safe-long-pass-42!'}, format='json').data
        self.client.credentials(HTTP_AUTHORIZATION='Bearer ' + pair['access'])
        r = self.client.post('/api/v1/auth/delete/', {'password': 'Safe-long-pass-42!'}, format='json')
        self.assertEqual(r.status_code, 204)
        self.user.refresh_from_db()
        self.store.refresh_from_db()
        self.product.refresh_from_db()
        self.assertFalse(self.user.is_active)
        self.assertNotIn('seller@example.invalid', self.user.email)
        self.assertFalse(self.user.has_usable_password())
        self.assertFalse(self.store.published)
        self.assertEqual(self.store.phone, '')
        self.assertEqual(self.store.payment_account, '')
        self.assertTrue(self.product.archived)
        self.assertEqual(self.product.photos.count(), 0)
        self.assertTrue(Order.objects.filter(pk=order.pk).exists())
        # The outstanding access token is rejected and the account can no longer sign in.
        self.assertEqual(self.client.get('/api/v1/seller/store/').status_code, 401)
        self.client.credentials()
        self.assertEqual(self.client.post('/api/v1/auth/login/',
            {'email': 'seller@example.invalid', 'password': 'Safe-long-pass-42!'}, format='json').status_code, 401)

    def test_store_create_once_and_protected_fields(self):
        self.seller(self.other)
        body = {'name': 'Second', 'slug': 'second', 'phone': '+252612345670', 'city': 'Demo', 'pickup_instructions': 'Point',
            'payment_provider': 'Other', 'payment_account': 'DEMO', 'payment_name': 'Demo', 'owner': self.user.pk, 'published': True, 'suspended': False}
        self.assertEqual(self.client.post('/api/v1/seller/store/', body).status_code, 201)
        self.assertEqual(self.client.post('/api/v1/seller/store/', body).status_code, 400)
        s = Store.objects.get(owner=self.other)
        self.assertFalse(s.published)
        s.suspended = True
        s.save()
        self.client.patch('/api/v1/seller/store/', {'suspended': False}, format='json')
        s.refresh_from_db()
        self.assertTrue(s.suspended)

    def test_tenant_isolation(self):
        order = self.order()
        self.seller(self.other)
        for path in [f'/api/v1/seller/products/{self.product.pk}/', f'/api/v1/seller/orders/{order.pk}/']:
            self.assertEqual(self.client.get(path).status_code, 404)
            self.assertIn(self.client.patch(path, {'stock': 100}, format='json').status_code, [404, 405])
        self.assertEqual(self.client.post(f'/api/v1/seller/orders/{order.pk}/act/', {'action': 'ACCEPTED'}).status_code, 404)
        self.assertEqual(self.client.post(f'/api/v1/seller/products/{self.product.pk}/photos/', {}).status_code, 404)
        self.assertEqual(self.client.get('/api/v1/seller/store/').status_code, 404)

    def test_hidden_products(self):
        for field in ['archived', 'moderated']:
            setattr(self.product, field, True)
            self.product.save()
            self.assertEqual(self.client.get(f'/api/v1/products/{self.product.pk}/').status_code, 404)
            setattr(self.product, field, False)
        self.product.published = False
        self.product.save()
        self.assertEqual(self.client.get(f'/api/v1/products/{self.product.pk}/').status_code, 404)
        self.store.suspended = True
        self.store.save()
        self.assertEqual(self.client.get('/api/v1/stores/demo/').status_code, 404)

    def test_invalid_product_and_photo(self):
        self.seller()
        for data in [{'price': '-1'}, {'stock': -1}, {'price': '0'}]:
            self.assertEqual(self.client.patch(f'/api/v1/seller/products/{self.product.pk}/', data).status_code, 400)
        upload = SimpleUploadedFile('fake.jpg', b'<script>bad</script>', content_type='image/jpeg')
        self.assertEqual(self.client.post(f'/api/v1/seller/products/{self.product.pk}/photos/', {'image': upload}).status_code, 400)

    def test_stale_stock_edit_cannot_overwrite_acceptance(self):
        self.seller()
        snapshot = self.client.get(f'/api/v1/seller/products/{self.product.pk}/').data
        order = self.order()
        transition(order.pk, self.user, 'ACCEPTED')
        r = self.client.patch(f'/api/v1/seller/products/{self.product.pk}/',
            {'stock': 8, 'expected_updated_at': snapshot['updated_at']}, format='json')
        self.assertEqual(r.status_code, 400)
        self.product.refresh_from_db()
        self.assertEqual(self.product.stock, 4)
        snapshot = self.client.get(f'/api/v1/seller/products/{self.product.pk}/').data
        r = self.client.patch(f'/api/v1/seller/products/{self.product.pk}/',
            {'stock': 8, 'expected_updated_at': snapshot['updated_at']}, format='json')
        self.assertEqual(r.status_code, 200, r.data)

    def test_product_without_store_is_404(self):
        self.seller(self.other)
        r = self.client.post('/api/v1/seller/products/', {'name': 'Tea', 'slug': 'tea', 'price': '5.00', 'stock': 1})
        self.assertEqual(r.status_code, 404)

    def test_photos_reencoded_and_limited(self):
        import tempfile
        self.seller()
        with tempfile.TemporaryDirectory() as root, override_settings(MEDIA_ROOT=root):
            for i in range(4):
                out = BytesIO()
                Image.new('RGB', (10, 10), 'red').save(out, 'PNG')
                upload = SimpleUploadedFile('original.png', out.getvalue(), content_type='image/png')
                result = self.client.post(f'/api/v1/seller/products/{self.product.pk}/photos/', {'image': upload})
                self.assertEqual(result.status_code, 200 if i < 3 else 400)
            self.assertTrue(self.product.photos.first().image.name.endswith('.jpg'))

    def test_corrupt_png_returns_validation_error(self):
        import base64
        self.seller()
        raw = base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aV1cAAAAASUVORK5CYII=')
        upload = SimpleUploadedFile('broken.png', raw, content_type='image/png')
        self.assertEqual(self.client.post(f'/api/v1/seller/products/{self.product.pk}/photos/', {'image': upload}).status_code, 400)

    def test_demo_seed_repeatable_and_disabled_in_production(self):
        from io import StringIO
        from django.core.management import call_command, CommandError
        with override_settings(DEBUG=True):
            call_command('seed_demo', stdout=StringIO())
            counts = (Store.objects.count(), Product.objects.count(), Order.objects.count())
            call_command('seed_demo', stdout=StringIO())
            self.assertEqual(counts, (Store.objects.count(), Product.objects.count(), Order.objects.count()))
        with override_settings(DEBUG=False), self.assertRaises(CommandError):
            call_command('seed_demo', stdout=StringIO())

    def test_checkout_snapshot_and_idempotency(self):
        data = data_for(self.store, self.product)
        quote = self.client.post('/api/v1/quote/', data, format='json')
        self.assertEqual(quote.status_code, 200, quote.data)
        payload = data | {'quote': quote.data['quote'], 'idempotency_key': str(uuid.uuid4()), 'total': '0.01', 'payment': 'PAID'}
        a = self.client.post('/api/v1/checkout/', payload, format='json')
        b = self.client.post('/api/v1/checkout/', payload, format='json')
        self.assertEqual(a.status_code, 201, a.data)
        self.assertEqual(a.data, b.data)
        self.assertEqual(Order.objects.count(), 1)
        order = Order.objects.get()
        self.assertEqual(str(order.total), '5.00')
        self.assertEqual(order.payment, 'UNPAID')
        self.product.price = '9.00'
        self.product.save()
        self.assertEqual(str(order.lines.get().unit_price), '5.00')
        self.assertEqual(self.client.get('/api/v1/checkout/'+payload['idempotency_key']+'/').status_code, 200)

    def test_price_change_requires_new_confirmation(self):
        data = data_for(self.store, self.product)
        quote = make_quote(self.guest, data)['quote']
        self.product.price = '8.00'
        self.product.save()
        with self.assertRaises(ValidationError):
            checkout(self.guest, data, uuid.uuid4(), quote)

    def test_expired_guest_can_recover_result_but_not_submit(self):
        order = self.order()
        self.guest.expires_at = timezone.now() - timedelta(days=1)
        self.guest.save()
        self.assertEqual(self.client.get(f'/api/v1/checkout/{order.idempotency_key}/').status_code, 200)
        result = self.client.post('/api/v1/quote/', data_for(self.store, self.product), format='json')
        self.assertIn(result.status_code, [401, 403])

    def test_quantities_and_mixed_store_rejected(self):
        for qty in [0, -1, 'bad', 1.5, 6]:
            self.assertEqual(self.client.post('/api/v1/quote/', data_for(self.store, self.product, qty), format='json').status_code, 400)
        other_store = Store.objects.create(owner=self.other, name='Other', slug='other', delivery_fee=0)
        p = Product.objects.create(store=other_store, name='Other', slug='other', price=1, stock=5)
        data = data_for(self.store, self.product)
        data['items'].append({'product': p.pk, 'quantity': 1})
        self.assertEqual(self.client.post('/api/v1/quote/', data, format='json').status_code, 400)

    def test_delivery_validation_and_fee(self):
        data = data_for(self.store, self.product) | {'fulfillment': 'delivery', 'region': 'Outside', 'address': 'Demo'}
        self.assertEqual(self.client.post('/api/v1/quote/', data, format='json').status_code, 400)
        data['region'] = 'Zone A'
        self.assertEqual(self.client.post('/api/v1/quote/', data, format='json').data['total'], '7.50')

    def test_accept_cancel_and_refund(self):
        order = self.order(2)
        self.product.refresh_from_db()
        self.assertEqual(self.product.stock, 5)
        transition(order.pk, self.user, 'ACCEPTED')
        transition(order.pk, self.user, 'ACCEPTED')
        self.product.refresh_from_db()
        self.assertEqual(self.product.stock, 3)
        transition(order.pk, self.user, 'PAID', confirmed=True, reference='MANUAL')
        transition(order.pk, self.user, 'CANCELLED')
        transition(order.pk, self.user, 'CANCELLED')
        order.refresh_from_db()
        self.product.refresh_from_db()
        self.assertEqual(self.product.stock, 5)
        self.assertEqual(order.payment, 'REFUND_REQUIRED')
        transition(order.pk, self.user, 'REFUNDED', confirmed=True)
        self.assertTrue(Event.objects.filter(order=order, action='REFUNDED', actor=self.user).exists())
        self.assertEqual(Event.objects.get(order=order, action='PAID').reference, 'MANUAL')

    def test_new_cancel_and_invalid_transition(self):
        order = self.order()
        with self.assertRaises(ValidationError):
            transition(order.pk, self.user, 'DELIVERED')
        transition(order.pk, self.user, 'CANCELLED')
        self.product.refresh_from_db()
        self.assertEqual(self.product.stock, 5)
        with self.assertRaises(ValidationError):
            transition(order.pk, self.user, 'ACCEPTED')

    def test_payment_requires_owner_and_confirmation(self):
        from rest_framework.exceptions import PermissionDenied
        order = self.order()
        transition(order.pk, self.user, 'ACCEPTED')
        with self.assertRaises(PermissionDenied):
            transition(order.pk, self.other, 'PAID', confirmed=True)
        with self.assertRaises(ValidationError):
            transition(order.pk, self.user, 'PAID')
        transition(order.pk, self.user, 'PREPARING')
        transition(order.pk, self.user, 'DELIVERED')
        order.refresh_from_db()
        self.assertEqual(order.payment, 'UNPAID')

    def test_all_lines_rollback(self):
        p2 = Product.objects.create(store=self.store, name='Rice', slug='rice', price=2, stock=2, published=True)
        data = data_for(self.store, self.product)
        data['items'].append({'product': p2.pk, 'quantity': 2})
        order = checkout(self.guest, data, uuid.uuid4(), make_quote(self.guest, data)['quote'])
        p2.stock = 0
        p2.save()
        with self.assertRaises(ValidationError):
            transition(order.pk, self.user, 'ACCEPTED')
        self.product.refresh_from_db()
        order.refresh_from_db()
        self.assertEqual(self.product.stock, 5)
        self.assertEqual(order.status, 'NEW')

    def test_suspended_store_existing_orders_can_cancel(self):
        order = self.order()
        self.store.suspended = True
        self.store.save()
        with self.assertRaises(ValidationError):
            transition(order.pk, self.user, 'ACCEPTED')
        self.seller()
        self.assertEqual(self.client.get(f'/api/v1/seller/orders/{order.pk}/').status_code, 200)
        transition(order.pk, self.user, 'CANCELLED')

    def test_tracking_privacy_and_payment_visibility(self):
        order = self.order()
        self.assertEqual(self.client.get('/api/v1/tracking/').status_code, 404)
        self.client.credentials(HTTP_X_TRACKING_TOKEN=order.tracking_token)
        result = self.client.get('/api/v1/tracking/')
        self.assertNotIn('phone', result.data)
        self.assertNotIn('address', result.data)
        self.assertIsNone(result.data['payment_instructions'])
        self.assertEqual(result['Cache-Control'], 'no-store')
        self.assertEqual(result['Referrer-Policy'], 'no-referrer')
        transition(order.pk, self.user, 'ACCEPTED')
        self.assertEqual(self.client.get('/api/v1/tracking/').data['payment_instructions']['account'], 'TEST-ACCOUNT')

    def test_admin_cannot_bypass_stock(self):
        order = self.order()
        self.assertIn('status', OrderAdmin(Order, AdminSite()).readonly_fields)
        self.assertIn('stock', ProductAdmin(Product, AdminSite()).readonly_fields)
        admin = User.objects.create_superuser('admin@example.invalid', 'Long-secret-46!', name='Admin')
        transition(order.pk, admin, 'ACCEPTED')
        self.product.refresh_from_db()
        self.assertEqual(self.product.stock, 4)
        transition(order.pk, admin, 'PAID', confirmed=True)
        transition(order.pk, admin, 'CORRECT_PAYMENT', reason='Mistaken receipt')
        self.assertTrue(Event.objects.filter(action='CORRECT_PAYMENT', reason__contains='Mistaken receipt').exists())

    def test_csrf_rate_limits_and_language(self):
        csrf_client = APIClient(enforce_csrf_checks=True)
        self.assertEqual(csrf_client.post('/admin/login/', {'username': 'x', 'password': 'y'}).status_code, 403)
        for _ in range(30):
            self.assertEqual(self.client.post('/api/v1/guest/').status_code, 201)
        self.assertEqual(self.client.post('/api/v1/guest/').status_code, 429)
        self.assertTrue(RateBucket.objects.exists())
        self.client.credentials()
        self.assertEqual(self.client.get('/api/v1/config/', HTTP_ACCEPT_LANGUAGE='so')['Content-Language'], 'so')
        self.assertEqual(self.client.get('/api/v1/config/', HTTP_ACCEPT_LANGUAGE='en')['Content-Language'], 'en')


@override_settings(SECURE_SSL_REDIRECT=False, LANGUAGE_CODE='en')
class ConcurrencyTests(TransactionTestCase):
    reset_sequences = True

    def setUp(self):
        self.user, self.other, self.store, self.product, self.guest = fixture()
        self.assertEqual(connection.vendor, 'postgresql', 'These tests require real PostgreSQL.')
        self.product.stock = 1
        self.product.save()

    def new_order(self):
        data = data_for(self.store, self.product)
        return checkout(self.guest, data, uuid.uuid4(), make_quote(self.guest, data)['quote'])

    def run_concurrent(self, ids):
        barrier = Barrier(2)
        def accept(pk):
            close_old_connections()
            try:
                actor = User.objects.get(pk=self.user.pk)
                barrier.wait(timeout=10)
                try:
                    transition(pk, actor, 'ACCEPTED')
                    return True
                except ValidationError:
                    return False
            finally:
                close_old_connections()
        with ThreadPoolExecutor(max_workers=2) as pool:
            return list(pool.map(accept, ids))

    def test_two_orders_do_not_oversell(self):
        a, b = self.new_order(), self.new_order()
        self.assertEqual(sum(self.run_concurrent([a.pk, b.pk])), 1)
        self.product.refresh_from_db()
        self.assertEqual(self.product.stock, 0)

    def test_same_order_deducts_once(self):
        order = self.new_order()
        self.assertEqual(self.run_concurrent([order.pk, order.pk]), [True, True])
        self.product.refresh_from_db()
        self.assertEqual(self.product.stock, 0)
        self.assertEqual(Event.objects.filter(order=order, action='ACCEPTED').count(), 1)

    def test_simultaneous_checkout_creates_one_order(self):
        data = data_for(self.store, self.product)
        signed = make_quote(self.guest, data)['quote']
        key, barrier = uuid.uuid4(), Barrier(2)
        def submit(_):
            close_old_connections()
            try:
                guest = GuestSession.objects.get(pk=self.guest.pk)
                barrier.wait(timeout=10)
                return checkout(guest, data, key, signed).pk
            finally:
                close_old_connections()
        with ThreadPoolExecutor(max_workers=2) as pool:
            ids = list(pool.map(submit, range(2)))
        self.assertEqual(ids[0], ids[1])
        self.assertEqual(Order.objects.count(), 1)
