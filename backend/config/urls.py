from django.conf import settings
from django.conf.urls.static import static
from django.contrib import admin
from django.urls import path, include
from django.views.generic import TemplateView
from rest_framework.routers import DefaultRouter
from drf_spectacular.views import SpectacularAPIView, SpectacularSwaggerView
from shop import views as v

router = DefaultRouter()
router.register('stores', v.PublicStores, basename='stores')
router.register('seller/products', v.MyProducts, basename='products')
router.register('seller/orders', v.MyOrders, basename='orders')
api = [path('', include(router.urls)), path('config/', v.Configuration.as_view()),
    path('auth/register/', v.RegisterView.as_view()), path('auth/login/', v.LoginView.as_view()),
    path('auth/refresh/', v.RefreshView.as_view()), path('auth/logout/', v.LogoutView.as_view()),
    path('auth/password/', v.PasswordView.as_view()), path('auth/reset/', v.ResetView.as_view()),
    path('auth/reset/confirm/', v.ResetConfirmView.as_view()), path('auth/delete/', v.DeleteAccountView.as_view()),
    path('seller/store/', v.MyStore.as_view()),
    path('seller/store/publish/', v.PublishView.as_view()), path('seller/store/logo/', v.LogoView.as_view()),
    path('seller/dashboard/', v.Dashboard.as_view()), path('products/<int:pk>/', v.PublicProduct.as_view()),
    path('guest/', v.GuestView.as_view()), path('quote/', v.QuoteView.as_view()),
    path('checkout/', v.CheckoutView.as_view()), path('checkout/<uuid:key>/', v.CheckoutResult.as_view()),
    path('tracking/', v.Tracking.as_view()), path('reports/', v.ReportView.as_view()),
    path('schema/', SpectacularAPIView.as_view(), name='schema'),
    path('docs/', SpectacularSwaggerView.as_view(url_name='schema'))]
_page_context = {'brand': settings.BRAND_NAME, 'support_email': settings.SUPPORT_EMAIL, 'publisher': settings.PUBLISHER_NAME}
urlpatterns = [path('admin/', admin.site.urls), path('api/v1/', include(api)),
    path('privacy/', TemplateView.as_view(template_name='shop/privacy.html', extra_context=_page_context), name='privacy'),
    path('account-deletion/', TemplateView.as_view(template_name='shop/account_deletion.html', extra_context=_page_context), name='account-deletion')]
if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
