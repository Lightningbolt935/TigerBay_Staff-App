/// Inserts a new row into `dishes` and returns the created row.
  Future<Map<String, dynamic>> insertDish({
    required String name,
    required double price,
    required String description,
    required String category,
    String? imageUrl,
  }) async {
    final response = await _client
        .from('dishes')
        .insert({
          'name': name,
          'price': price,
          'description': description,
          'category': category,
          if (imageUrl != null) 'image_url': imageUrl,
        })
        .select()
        .single();
    return Map<String, dynamic>.from(response as Map);
  }

  /// Updates an existing `dishes` row by its bigint [id].
  Future<void> updateDish({
    required int id,
    required String name,
    required double price,
    required String description,
    required String category,
    String? imageUrl,
  }) async {
    await _client.from('dishes').update({
      'name': name,
      'price': price,
      'description': description,
      'category': category,
      'image_url': imageUrl,
    }).eq('id', id);
  }