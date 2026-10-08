import hashlib
import secrets
import uuid
from datetime import timedelta
from django.conf import settings
from django.core.management.base import BaseCommand, CommandError
from django.utils import timezone
from shop.models import User, Store, Product, GuestSession
from shop.services import make_quote, checkout


class Command(BaseCommand):
    help = 'Development-only idempotent demo data. Generated passwords are printed once.'

    def add_arguments(self, parser):
        parser.add_argument('--password')

    def handle(self, *args, **options):
        if not settings.DEBUG:
            raise CommandError('Demo data is disabled outside DEBUG.')
        for i, name in enumerate(['Suuqa Tijaabo', 'Dukaan Tijaabo'], 1):
            email = f'seller{i}@example.invalid'
            user = User.objects.filter(email=email).first()
            if not user:
                password = options['password'] or secrets.token_urlsafe(18)
                user = User.objects.create_user(email, password, name=f'Demo seller {i}')
                self.stdout.write(f'{email} password: {password}')
            store, _ = Store.objects.get_or_create(owner=user, defaults={'name': name, 'slug': f'demo-{i}',
                'phone': '+252610000000', 'city': 'Demo city', 'delivery_regions': ['Demo zone'],
                'pickup_instructions': 'Demo pickup point', 'delivery_fee': '2.00',
                'payment_provider': 'Other', 'payment_account': 'DEMO-NOT-PAYABLE', 'payment_name': 'Demo only', 'published': True})
            for j, product_name in enumerate(['Shaah', 'Bariis', 'Sonkor'], 1):
                Product.objects.get_or_create(store=store, slug=f'product-{j}', defaults={
                    'name': product_name, 'price': f'{j * 3}.50', 'stock': 20, 'published': True, 'category': 'Cunto'})
            if not store.orders.exists():
                guest = GuestSession.objects.create(digest=hashlib.sha256(secrets.token_bytes(32)).hexdigest(),
                    expires_at=timezone.now() + timedelta(days=30))
                data = {'store': store.pk, 'items': [{'product': store.products.first().pk, 'quantity': 1}],
                    'customer_name': 'Demo customer', 'phone': '+252610000000', 'fulfillment': 'pickup', 'region': '', 'address': '', 'note': ''}
                quote = make_quote(guest, data)
                checkout(guest, data, uuid.uuid4(), quote['quote'])
            self.stdout.write(f'Store code: {store.slug}')
