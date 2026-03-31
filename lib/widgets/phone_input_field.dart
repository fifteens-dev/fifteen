import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';
import '../constants/app_dimensions.dart';
import '../utils/context_menu_builder.dart';

/// 電話番号入力フィールドウィジェット
class PhoneInputField extends StatefulWidget {
  final TextEditingController controller;
  final String countryCode;
  final VoidCallback? onCountryCodeTap;

  const PhoneInputField({
    super.key,
    required this.controller,
    this.countryCode = '+81',
    this.onCountryCodeTap,
  });

  @override
  State<PhoneInputField> createState() => _PhoneInputFieldState();
}

class _PhoneInputFieldState extends State<PhoneInputField> {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppDimensions.inputFieldHeight,
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border.all(
          color: AppColors.border,
          width: AppDimensions.borderWidth,
        ),
        borderRadius: BorderRadius.circular(AppDimensions.borderRadiusMedium),
      ),
      child: Row(
        children: [
          // 国旗セレクター部分
          InkWell(
            onTap: widget.onCountryCodeTap,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimensions.paddingMedium,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '🇯🇵', // 日本の国旗
                    style: const TextStyle(fontSize: 24),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.keyboard_arrow_down,
                    color: AppColors.textPrimary,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          // 区切り線
          Container(
            width: 1,
            height: AppDimensions.inputFieldHeight * 0.6,
            color: AppColors.border,
          ),
          // 電話番号入力部分
          Expanded(
            child: TextField(
              controller: widget.controller,
              style: AppTextStyles.input,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                _PhoneNumberFormatter(),
              ],
              contextMenuBuilder: buildTextContextMenu,
              decoration: InputDecoration(
                hintText: '080-1234-5678',
                hintStyle: AppTextStyles.placeholder,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppDimensions.paddingMedium,
                  vertical: AppDimensions.paddingMedium,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 電話番号のフォーマッター（ハイフン自動挿入）
class _PhoneNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) {
      return newValue;
    }

    // 数字のみ取得
    final digitsOnly = text.replaceAll(RegExp(r'\D'), '');

    // フォーマット適用
    String formatted = '';
    if (digitsOnly.length >= 1) {
      formatted = digitsOnly.substring(0, digitsOnly.length.clamp(0, 3));
    }
    if (digitsOnly.length >= 4) {
      formatted += '-${digitsOnly.substring(3, digitsOnly.length.clamp(3, 7))}';
    }
    if (digitsOnly.length >= 8) {
      formatted += '-${digitsOnly.substring(7, digitsOnly.length.clamp(7, 11))}';
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
