class Deal {
  final String id;
  final String title;
  final String description;
  final double? price;
  final double? originalPrice;
  final int? discount;
  final String currency;
  final String? image;
  final String source;
  final String brand;
  final String seller;
  final String? url;
  final double? rating;
  final int? reviewsCount;
  final bool inStock;
  final bool isSaved;
  final String shipping;
  final String condition;
  final List<String> features;
  final double? distanceMiles;
  final String locationName;

  Deal({
    required this.id,
    required this.title,
    this.description = '',
    this.price,
    this.originalPrice,
    this.discount,
    this.currency = 'USD',
    this.image,
    this.source = '',
    this.brand = '',
    this.seller = '',
    this.url,
    this.rating,
    this.reviewsCount,
    this.inStock = true,
    this.isSaved = false,
    this.shipping = '',
    this.condition = '',
    this.features = const [],
    this.distanceMiles,
    this.locationName = '',
  });

  factory Deal.fromJson(Map<String, dynamic> json) {
    // Check multiple possible image field names; skip empty strings
    final rawImage = _firstNonEmpty([
      json['image'],
      json['image_url'],
      json['product_photo'],
      json['thumbnail'],
    ]);
    final imageUrl = (rawImage is String && rawImage.isNotEmpty) ? rawImage : null;
    
    return Deal(
      id: json['id']?.toString() ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      price: _parseDouble(json['price']),
      originalPrice: _parseDouble(json['original_price']),
      discount: json['discount'] as int?,
      currency: json['currency'] ?? 'USD',
      image: imageUrl,
      source: json['source'] ?? '',
      brand: json['brand'] ?? json['merchant_name'] ?? '',
      seller: json['seller'] ?? '',
      url: json['url'],
      rating: _parseDouble(json['rating']),
      reviewsCount: json['reviews_count'] as int?,
      inStock: json['in_stock'] ?? true,
      isSaved: json['is_saved'] ?? false,
      shipping: json['shipping'] ?? '',
      condition: json['condition'] ?? '',
      features: (json['features'] as List<dynamic>?)
              ?.map((f) => f.toString())
              .toList() ??
          [],
      distanceMiles: _parseDouble(json['distance_miles']),
      locationName: json['location_name'] ?? '',
    );
  }

  Deal copyWith({bool? isSaved}) {
    return Deal(
      id: id,
      title: title,
      description: description,
      price: price,
      originalPrice: originalPrice,
      discount: discount,
      currency: currency,
      image: image,
      source: source,
      brand: brand,
      seller: seller,
      url: url,
      rating: rating,
      reviewsCount: reviewsCount,
      inStock: inStock,
      isSaved: isSaved ?? this.isSaved,
      shipping: shipping,
      condition: condition,
      features: features,
      distanceMiles: distanceMiles,
      locationName: locationName,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'price': price,
      'original_price': originalPrice,
      'image_url': image,
      'source': source,
      'brand': brand,
      'seller': seller,
      'url': url,
      'shipping': shipping,
      'condition': condition,
      'features': features,
    };
  }

  String get formattedPrice {
    if (price == null) return 'N/A';
    return '\$${price!.toStringAsFixed(2)}';
  }

  String get formattedOriginalPrice {
    if (originalPrice == null) return '';
    return '\$${originalPrice!.toStringAsFixed(2)}';
  }

  bool get hasDiscount => discountPercent > 0;

  /// Computed discount percentage from price and original price, or existing field.
  int get discountPercent {
    if (discount != null && discount! > 0) return discount!;
    if (price != null && originalPrice != null && originalPrice! > 0 && price! < originalPrice!) {
      return (((originalPrice! - price!) / originalPrice!) * 100).round();
    }
    return 0;
  }

  String get formattedDiscount => '$discountPercent% OFF';

  bool get isFromMarketplace => source == 'Facebook Marketplace';

  String? get formattedDistance {
    if (distanceMiles == null) return null;
    if (distanceMiles! < 0.1) return 'Nearby';
    if (distanceMiles! < 1) return '${(distanceMiles! * 10).round() / 10} mi away';
    return '${distanceMiles!.round()} mi away';
  }

  /// Generates a trending reason tag based on deal attributes.
  String get trendingTag {
    // Top brands
    const topBrands = ['nike', 'adidas', 'zara', 'h&m', 'mango', 'uniqlo',
      'lululemon', 'alo', 'gucci', 'prada', 'quince', 'gap', 'asos'];
    final srcLower = source.toLowerCase();
    final titleLower = title.toLowerCase();

    // Huge discount
    if (discountPercent >= 50) return '#HugeSale';
    if (discountPercent >= 30) return '#GoodDeal';

    // Top brand on discount
    if (topBrands.any((b) => srcLower.contains(b)) && discountPercent > 0) {
      return '#TopBrandDeal';
    }

    // Category-based tags
    if (titleLower.contains('sport') || titleLower.contains('athletic') ||
        titleLower.contains('running') || titleLower.contains('gym')) {
      return '#TrendingSport';
    }
    if (titleLower.contains('casual') || titleLower.contains('everyday')) {
      return '#CasualFavorite';
    }

    // Price check
    if (price != null && price! < 50) return '#ValueForPrice';
    if (price != null && price! < 25) return '#BudgetFind';

    // Rating based
    if (rating != null && rating! >= 4.5) return '#TopRated';
    if (rating != null && rating! >= 4.0) return '#HighlyRated';

    return '#Trending';
  }

  /// Returns the first non-null, non-empty string from [candidates].
  static String? _firstNonEmpty(List<dynamic> candidates) {
    for (final c in candidates) {
      if (c is String && c.isNotEmpty) return c;
    }
    return null;
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}

class SearchResult {
  final List<Deal> deals;
  final int total;
  final String query;
  final int searchTimeMs;
  final List<String> sourcesSearched;
  final String? quotaWarning;
  final Map<String, dynamic>? extracted;
  final List<String>? searchQueries;
  
  // Pagination
  final bool hasMore;
  final int offset;
  final int limit;

  SearchResult({
    required this.deals,
    required this.total,
    this.query = '',
    this.searchTimeMs = 0,
    this.sourcesSearched = const [],
    this.quotaWarning,
    this.extracted,
    this.searchQueries,
    this.hasMore = false,
    this.offset = 0,
    this.limit = 20,
  });

  factory SearchResult.fromJson(Map<String, dynamic> json) {
    return SearchResult(
      deals: (json['deals'] as List<dynamic>?)
              ?.map((d) => Deal.fromJson(d as Map<String, dynamic>))
              .toList() ??
          [],
      total: json['total'] ?? 0,
      query: json['query'] ?? '',
      searchTimeMs: json['search_time_ms'] ?? 0,
      sourcesSearched: (json['sources_searched'] as List<dynamic>?)
              ?.map((s) => s.toString())
              .toList() ??
          [],
      quotaWarning: json['quota_warning'],
      extracted: json['extracted'] as Map<String, dynamic>?,
      searchQueries: (json['search_queries'] as List<dynamic>?)
          ?.map((s) => s.toString())
          .toList(),
      hasMore: json['has_more'] ?? false,
      offset: json['offset'] ?? 0,
      limit: json['limit'] ?? 20,
    );
  }
}
