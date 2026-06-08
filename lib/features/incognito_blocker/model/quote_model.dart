import 'dart:convert';
import 'dart:math';
import 'dart:developer' as developer;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Data model for a single quote.
class QuoteModel {
  final String text;
  final String author;
  final String category;

  const QuoteModel({
    required this.text,
    required this.author,
    required this.category,
  });

  /// Deserialize from JSON map.
  factory QuoteModel.fromJson(Map<String, dynamic> json) {
    return QuoteModel(
      text: json['text'] as String,
      author: json['author'] as String,
      category: json['category'] as String,
    );
  }

  /// Serialize to JSON map.
  Map<String, dynamic> toJson() => {'text': text, 'author': author, 'category': category};

  @override
  String toString() => 'QuoteModel(text: "$text", author: "$author")';
}
