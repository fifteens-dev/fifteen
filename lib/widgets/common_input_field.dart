import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';
import '../constants/app_dimensions.dart';
import '../utils/context_menu_builder.dart';

/// 汎用的な入力フィールドウィジェット
class CommonInputField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final TextInputType keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLines;
  final int? maxLength;
  final String? Function(String?)? validator;
  final bool autocorrect;
  final bool enableSuggestions;

  const CommonInputField({
    super.key,
    required this.controller,
    required this.hintText,
    this.keyboardType = TextInputType.text,
    this.inputFormatters,
    this.maxLines = 1,
    this.maxLength,
    this.validator,
    this.autocorrect = true,
    this.enableSuggestions = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border.all(
          color: AppColors.border,
          width: AppDimensions.borderWidth,
        ),
        borderRadius: BorderRadius.circular(AppDimensions.borderRadiusMedium),
      ),
      child: TextFormField(
        controller: controller,
        style: AppTextStyles.input,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        autocorrect: autocorrect,
        enableSuggestions: enableSuggestions,
        maxLines: maxLines,
        maxLength: maxLength,
        validator: validator,
        contextMenuBuilder: buildTextContextMenu,
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: AppTextStyles.placeholder,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.paddingMedium,
            vertical: AppDimensions.paddingMedium,
          ),
          counterText: '', // 文字数カウンターを非表示
          errorStyle: const TextStyle(
            color: AppColors.error,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
