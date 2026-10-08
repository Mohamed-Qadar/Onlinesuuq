import hashlib
import time
import warnings
from io import BytesIO
from uuid import uuid4
from PIL import Image, ImageOps, UnidentifiedImageError
from django.core.files.base import ContentFile
from django.db import transaction
from django.utils.translation import gettext as _
from rest_framework.exceptions import Throttled, ValidationError
from rest_framework.views import exception_handler as drf_handler
from .models import RateBucket


def rate_limit(request, scope, limit=30, seconds=3600):
    # Do not trust arbitrary X-Forwarded-For. Configure a trusted proxy before deployment.
    ident = request.META.get('REMOTE_ADDR', 'unknown')
    key = hashlib.sha256(f'{scope}:{ident}:{int(time.time()) // seconds}'.encode()).hexdigest()
    with transaction.atomic():
        bucket, _created = RateBucket.objects.get_or_create(key=key)
        bucket = RateBucket.objects.select_for_update().get(pk=bucket.pk)
        if bucket.count >= limit:
            raise Throttled(wait=seconds)
        bucket.count += 1
        bucket.save(update_fields=['count'])


def clean_image(upload):
    if upload.size > 5 * 1024 * 1024:
        raise ValidationError(_('Images must be at most 5 MB.'))
    try:
        with warnings.catch_warnings():
            warnings.simplefilter('error', Image.DecompressionBombWarning)
            img = Image.open(upload)
            if img.format not in ['JPEG', 'PNG', 'WEBP'] or img.width * img.height > 20_000_000:
                raise ValueError()
            img.verify()
            upload.seek(0)
            img = ImageOps.exif_transpose(Image.open(upload)).convert('RGB')
            img.thumbnail((1600, 1600))
            out = BytesIO()
            img.save(out, 'JPEG', quality=85)
            return ContentFile(out.getvalue(), name=f'{uuid4().hex}.jpg')
    except (UnidentifiedImageError, OSError, ValueError, SyntaxError, Image.DecompressionBombError, Image.DecompressionBombWarning):
        raise ValidationError(_('Upload a valid JPEG, PNG or WebP image.'))


def exception_handler(exc, context):
    response = drf_handler(exc, context)
    if response is not None:
        response.data = {'errors': response.data}
    return response


class PrivacyMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        response = self.get_response(request)
        if request.path.startswith('/api/'):
            response['Cache-Control'] = 'no-store'
            response['X-Robots-Tag'] = 'noindex, nofollow'
            response['Referrer-Policy'] = 'no-referrer'
        return response
