import 'package:fitrope_app/style.dart';
import 'package:flutter/material.dart';

class CustomTextField extends StatelessWidget {
  final String hintText;
  final TextEditingController controller;
  final bool obscureText;
  const CustomTextField({super.key, required this.controller, this.hintText="", this.obscureText=false});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      cursorColor: ghostColor,
      decoration: InputDecoration(
        filled: true,
        isDense: true,
        contentPadding: const EdgeInsets.all(10),
        fillColor: secondaryColor,
        hintText: hintText,
        hintStyle: const TextStyle(color: ghostColor),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: ghostColor),
        )
      ),
      obscureText: obscureText
    );
  }
}