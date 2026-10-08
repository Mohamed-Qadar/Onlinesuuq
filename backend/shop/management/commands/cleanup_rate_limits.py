from datetime import timedelta
from django.core.management.base import BaseCommand
from django.utils import timezone
from shop.models import RateBucket


class Command(BaseCommand):
    help = 'Remove rate counters older than two days; never touches active hourly buckets.'

    def handle(self, *args, **options):
        count, _ = RateBucket.objects.filter(created_at__lt=timezone.now() - timedelta(days=2)).delete()
        self.stdout.write(f'Removed {count} expired rate counters.')
