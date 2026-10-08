class Store {
  final int id;
  final String name, slug, description, phone, city, pickup, deliveryFee;
  final List<String> regions;
  final Map<String, dynamic> json;
  Store.fromJson(this.json)
    : id = json['id'] as int,
      name = json['name'] as String,
      slug = json['slug'] as String,
      description = json['description'] as String? ?? '',
      phone = json['phone'] as String? ?? '',
      city = json['city'] as String? ?? '',
      pickup = json['pickup_instructions'] as String? ?? '',
      deliveryFee = json['delivery_fee'] as String? ?? '0.00',
      regions = List<String>.from(json['delivery_regions'] as List? ?? []);
}

class Product {
  final int id, storeId, stock;
  final String name, price, description, category;
  final List<String> images;
  final Map<String, dynamic> json;
  Product.fromJson(this.json)
    : id = json['id'] as int,
      storeId = json['store'] as int,
      stock = json['stock'] as int,
      name = json['name'] as String,
      price = json['price'] as String,
      description = json['description'] as String? ?? '',
      category = json['category'] as String? ?? '',
      images = (json['photos'] as List? ?? [])
          .map((p) => p['image'] as String)
          .toList();
}

class CartLine {
  final Product product;
  int quantity;
  CartLine(this.product, this.quantity);
  Map<String, dynamic> toJson() => {
    'product': product.json,
    'quantity': quantity,
  };
}

class OrderSummary {
  final String reference, status, payment, total;
  final Map<String, dynamic> json;
  OrderSummary.fromJson(this.json)
    : reference = json['reference'] as String,
      status = json['status'] as String,
      payment = json['payment'] as String,
      total = json['total'] as String;
}

class CheckoutRequest {
  final int store;
  final List<CartLine> lines;
  final Map<String, String> customer;
  CheckoutRequest(this.store, this.lines, this.customer);
  Map<String, dynamic> toJson() => {
    'store': store,
    'items': lines
        .map((l) => {'product': l.product.id, 'quantity': l.quantity})
        .toList(),
    ...customer,
  };
}
