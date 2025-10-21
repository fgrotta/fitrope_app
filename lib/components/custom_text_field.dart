import 'package:fitrope_app/style.dart';
import 'package:flutter/material.dart';

class CustomTextField extends StatelessWidget {
  final String hintText;
  final TextEditingController controller;
  final bool obscureText;
  final void Function(PointerDownEvent _)? onTapOutside;
  final bool disabled;
  const CustomTextField({super.key, required this.controller, this.hintText="", this.obscureText=false, this.onTapOutside, this.disabled=false});

  @override
  Widget build(BuildContext context) {
    return TextField(
      readOnly: disabled,
      onTapOutside: onTapOutside ?? (_) {},
      controller: controller,
      style: const TextStyle(color: Colors.white),
      cursorColor: onHintColor,
      decoration: InputDecoration(
        filled: true,
        isDense: true,
        contentPadding: const EdgeInsets.all(10),
        fillColor: onSurfaceColor,
        hintText: hintText,
        hintStyle: const TextStyle(color: onHintColor),
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