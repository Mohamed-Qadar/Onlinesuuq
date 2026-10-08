from django.db import transaction
from rest_framework.exceptions import AuthenticationFailed
from rest_framework_simplejwt.authentication import JWTAuthentication
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer, TokenRefreshSerializer
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.exceptions import TokenError
from .models import User
from django.utils.translation import gettext as _
from drf_spectacular.extensions import OpenApiAuthenticationExtension


class VersionedJWTAuthentication(JWTAuthentication):
    def get_user(self, validated_token):
        user = super().get_user(validated_token)
        if validated_token.get('version') != user.session_version:
            raise AuthenticationFailed(_('Session expired.'))
        return user


class VersionedJWTScheme(OpenApiAuthenticationExtension):
    target_class = 'shop.auth.VersionedJWTAuthentication'
    name = 'jwtAuth'

    def get_security_definition(self, auto_schema):
        return {'type': 'http', 'scheme': 'bearer', 'bearerFormat': 'JWT'}


class LoginSerializer(TokenObtainPairSerializer):
    @classmethod
    def get_token(cls, user):
        token = super().get_token(user)
        token['version'] = user.session_version
        return token

    def validate(self, attrs):
        attrs['email'] = attrs['email'].strip().lower()
        return super().validate(attrs)


class RefreshSerializer(TokenRefreshSerializer):
    @transaction.atomic
    def validate(self, attrs):
        try:
            token = RefreshToken(attrs['refresh'])
            user = User.objects.select_for_update().get(pk=token['user_id'])
            # Re-check blacklist after acquiring the lock: rotating refresh is single-use.
            token.check_blacklist()
            if not user.is_active or token.get('version') != user.session_version:
                raise AuthenticationFailed(_('Session expired.'))
            return super().validate(attrs)
        except (TokenError, User.DoesNotExist):
            raise AuthenticationFailed(_('Session expired.'))
