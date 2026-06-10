import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:stacked/stacked.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/models/vehicle_catalog_item.dart';
import 'package:webapp/requests/vehicle.request.dart';
import 'package:webapp/utils/functions.dart';
import 'package:webapp/view_models/auth/auth.vm.dart';
import 'package:webapp/widgets/admin_form_controls.dart';
import 'package:webapp/widgets/shared/app_page_loading.dart';
import 'package:webapp/widgets/shared/app_snackbar.dart';

class AuthView extends StatefulWidget {
  const AuthView({super.key, required this.onAuthenticated});

  final ValueChanged<UserModel> onAuthenticated;

  @override
  State<AuthView> createState() => _AuthViewState();
}

class _AuthViewState extends State<AuthView> {
  final _loginFormKey = GlobalKey<FormState>();
  final _registerFormKey = GlobalKey<FormState>();

  final _loginEmailController = TextEditingController();
  final _loginPasswordController = TextEditingController();
  final _registerEmailController = TextEditingController();
  final _registerNameController = TextEditingController();
  final _registerPhoneController = TextEditingController();
  final _registerLicenseController = TextEditingController();
  final _registerLatController = TextEditingController();
  final _registerLngController = TextEditingController();
  final _registerPasswordController = TextEditingController();

  String? _registerRole;
  String? _registerVehicleTypeId;
  bool _isLoginMode = true;
  bool _isLoadingVehicleTypes = true;
  List<VehicleCatalogItem> _vehicleTypes = const [];

  static const _roleOptions = ['client', 'driver', 'helper'];

  @override
  void initState() {
    super.initState();
    _loadVehicleTypes();
  }

  Future<void> _loadVehicleTypes() async {
    try {
      final vehicleTypes = await VehicleRequest.instance.getTypes();
      if (!mounted) {
        return;
      }
      setState(() {
        _vehicleTypes = vehicleTypes;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingVehicleTypes = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _loginEmailController.dispose();
    _loginPasswordController.dispose();
    _registerEmailController.dispose();
    _registerNameController.dispose();
    _registerPhoneController.dispose();
    _registerLicenseController.dispose();
    _registerLatController.dispose();
    _registerLngController.dispose();
    _registerPasswordController.dispose();
    super.dispose();
  }

  void _resetLoginFields() {
    _loginEmailController.clear();
    _loginPasswordController.clear();
  }

  void _resetRegisterFields() {
    _registerEmailController.clear();
    _registerNameController.clear();
    _registerPhoneController.clear();
    _registerLicenseController.clear();
    _registerLatController.clear();
    _registerLngController.clear();
    _registerPasswordController.clear();
    _registerRole = null;
    _registerVehicleTypeId = null;
  }

  void _switchAuthMode() {
    setState(() {
      _isLoginMode = !_isLoginMode;
      _resetLoginFields();
      _resetRegisterFields();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<AuthViewModel>.reactive(
      viewModelBuilder: AuthViewModel.new,
      builder: (context, vm, child) {
        final isBusy = vm.isBusy;
        if (isBusy) {
          return const Scaffold(
            backgroundColor: AppColors.primaryColor,
            body: SafeArea(
              child: AppPageLoading(message: 'Loading, please wait ...'),
            ),
          );
        }

        return Scaffold(
          backgroundColor: AppColors.primaryColor,
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(28, 26, 28, 28),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppColors.primaryBorder),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x120E0A1F),
                          blurRadius: 32,
                          offset: Offset(0, 18),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: AppColors.primaryColor,
                                shape: BoxShape.circle,
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x1F5B34D6),
                                    blurRadius: 18,
                                    offset: Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.local_shipping_rounded,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Paltranco',
                                    style: TextStyle(
                                      color: AppColors.primaryColor,
                                      fontSize: 25,
                                      fontWeight: FontWeight.w800,
                                      height: 1.2,
                                    ),
                                  ),
                                  const Text(
                                    'Digital Platform',
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                      height: 1.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeIn,
                          child: _isLoginMode
                              ? Form(
                                  key: _loginFormKey,
                                  child: Column(
                                    key: const ValueKey('login_form'),
                                    children: [
                                      _AuthTextField(
                                        controller: _loginEmailController,
                                        label: 'Email',
                                        keyboardType:
                                            TextInputType.emailAddress,
                                      ),
                                      const SizedBox(height: 14),
                                      _AuthTextField(
                                        controller: _loginPasswordController,
                                        label: 'Password',
                                        obscureText: true,
                                      ),
                                    ],
                                  ),
                                )
                              : _isLoadingVehicleTypes
                              ? const SizedBox(
                                  key: ValueKey('register_loading'),
                                  height: 220,
                                  child: AppPageLoading(
                                    message: 'Loading vehicle types...',
                                    compact: true,
                                    padding: EdgeInsets.zero,
                                  ),
                                )
                              : Form(
                                  key: _registerFormKey,
                                  child: Column(
                                    key: const ValueKey('register_form'),
                                    children: [
                                      _AuthDropdownField(
                                        label: 'Role',
                                        value: _registerRole,
                                        items: _roleOptions,
                                        onChanged: (value) {
                                          setState(() {
                                            _registerRole = value;
                                            if (value != 'driver') {
                                              _registerVehicleTypeId = null;
                                            }
                                          });
                                        },
                                      ),
                                      if (_registerRole == 'driver') ...[
                                        const SizedBox(height: 14),
                                        _AuthDropdownField(
                                          label: 'Vehicle Type',
                                          value: _registerVehicleTypeId,
                                          items: _vehicleTypes
                                              .map((item) => item.id ?? '')
                                              .where(
                                                (value) => value.isNotEmpty,
                                              )
                                              .toList(),
                                          itemLabelBuilder: (value) {
                                            final match = _vehicleTypes.where(
                                              (item) => item.id == value,
                                            );
                                            if (match.isEmpty) {
                                              return value;
                                            }
                                            final item = match.first;
                                            final name =
                                                item.name?.trim() ?? '';
                                            final slug =
                                                item.slug?.trim() ?? '';
                                            if (name.isEmpty) {
                                              return slug;
                                            }
                                            if (slug.isEmpty) {
                                              return name;
                                            }
                                            return '$name ($slug)';
                                          },
                                          onChanged: (value) {
                                            setState(
                                              () => _registerVehicleTypeId =
                                                  value,
                                            );
                                          },
                                        ),
                                      ],
                                      const SizedBox(height: 14),
                                      _AuthTextField(
                                        controller: _registerEmailController,
                                        label: 'Email',
                                        keyboardType:
                                            TextInputType.emailAddress,
                                      ),
                                      const SizedBox(height: 14),
                                      _AuthTextField(
                                        controller: _registerNameController,
                                        label: 'Name',
                                        textCapitalization:
                                            TextCapitalization.words,
                                        inputFormatters: const [
                                          NameCaseTextInputFormatter(),
                                        ],
                                      ),
                                      const SizedBox(height: 14),
                                      _AuthTextField(
                                        controller: _registerPhoneController,
                                        label: 'Phone',
                                        keyboardType: TextInputType.phone,
                                        inputFormatters: const [
                                          PhilippinesPhoneInputFormatter(),
                                        ],
                                      ),
                                      if (_registerRole == 'driver') ...[
                                        const SizedBox(height: 14),
                                        _AuthTextField(
                                          controller:
                                              _registerLicenseController,
                                          label: 'License',
                                        ),
                                        const SizedBox(height: 14),
                                        _AuthTextField(
                                          controller: _registerLatController,
                                          label: 'Latitude',
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                                signed: true,
                                              ),
                                        ),
                                        const SizedBox(height: 14),
                                        _AuthTextField(
                                          controller: _registerLngController,
                                          label: 'Longitude',
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                                signed: true,
                                              ),
                                        ),
                                      ],
                                      const SizedBox(height: 14),
                                      _AuthTextField(
                                        controller: _registerPasswordController,
                                        label: 'Password',
                                        obscureText: true,
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                        const SizedBox(height: 22),
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 52,
                                child: OutlinedButton(
                                  onPressed: isBusy ? null : _switchAuthMode,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.primaryColor,
                                    side: const BorderSide(
                                      color: AppColors.primaryBorder,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                  ),
                                  child: Text(
                                    _isLoginMode
                                        ? 'Create Account'
                                        : 'Back to Login',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: SizedBox(
                                height: 52,
                                child: FilledButton(
                                  onPressed: isBusy ? null : () => _submit(vm),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.primaryColor,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                  ),
                                  child: isBusy
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.4,
                                            color: Colors.white,
                                          ),
                                        )
                                      : Text(
                                          _isLoginMode ? 'Login' : 'Register',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _submit(AuthViewModel vm) async {
    if (_isLoginMode) {
      final validationMessage = _loginValidationMessage();
      if (validationMessage != null) {
        AppSnackbar.showError(context, validationMessage);
        return;
      }
      final user = await vm.login(
        email: _loginEmailController.text.trim(),
        password: _loginPasswordController.text,
      );
      if (user != null) {
        widget.onAuthenticated(user);
      } else if (mounted && vm.errorMessage?.isNotEmpty == true) {
        AppSnackbar.showError(context, vm.errorMessage!);
      }
      return;
    }

    final validationMessage = _registerValidationMessage();
    if (validationMessage != null) {
      AppSnackbar.showError(context, validationMessage);
      return;
    }
    final isPendingRole =
        _registerRole == 'driver' || _registerRole == 'helper';
    final selectedVehicleType = _vehicleTypes.where(
      (item) => item.id == _registerVehicleTypeId,
    );
    final resolvedVehicleType = selectedVehicleType.isEmpty
        ? null
        : selectedVehicleType.first;
    final normalizedPhone =
        normalizePhilippinePhone(_registerPhoneController.text) ??
        _registerPhoneController.text.trim();
    final user = await vm.register(
      _registerRole == 'driver'
          ? DriverModel(
              role: _registerRole,
              email: _registerEmailController.text.trim(),
              name: _registerNameController.text.trim(),
              phone: normalizedPhone,
              password: _registerPasswordController.text,
              license: _registerLicenseController.text.trim(),
              lat: _tryParseDouble(_registerLatController.text),
              lng: _tryParseDouble(_registerLngController.text),
              vehicleType: resolvedVehicleType,
              isActive: !isPendingRole,
              isOnline: false,
            )
          : UserModel(
              role: _registerRole,
              email: _registerEmailController.text.trim(),
              name: _registerNameController.text.trim(),
              phone: normalizedPhone,
              password: _registerPasswordController.text,
              isActive: !isPendingRole,
              isOnline: false,
            ),
    );
    if (user != null) {
      if (user.isActive ?? false) {
        widget.onAuthenticated(user);
      } else {
        if (!mounted) {
          return;
        }
        AppSnackbar.showSuccess(
          context,
          'Account created. Please wait for admin approval before logging in.',
        );
        setState(() {
          _isLoginMode = true;
          _resetLoginFields();
          _resetRegisterFields();
        });
      }
    } else if (mounted && vm.errorMessage?.isNotEmpty == true) {
      AppSnackbar.showError(context, vm.errorMessage!);
    }
  }

  String? _loginValidationMessage() {
    return _validateEmail(_loginEmailController.text) ??
        _validatePassword(_loginPasswordController.text);
  }

  String? _registerValidationMessage() {
    return _validateRequired('Role')(_registerRole) ??
        (_registerRole == 'driver'
            ? _validateRequired('Vehicle type')(_registerVehicleTypeId)
            : null) ??
        _validateEmail(_registerEmailController.text) ??
        _validateRequired('Name')(_registerNameController.text) ??
        _validatePhone(_registerPhoneController.text) ??
        (_registerRole == 'driver'
            ? _validateLicense(_registerLicenseController.text)
            : null) ??
        (_registerRole == 'driver'
            ? _validateLatitude(_registerLatController.text)
            : null) ??
        (_registerRole == 'driver'
            ? _validateLongitude(_registerLngController.text)
            : null) ??
        _validatePassword(_registerPasswordController.text);
  }

  String? _validateEmail(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return 'Email is required.';
    }
    final emailRegex = RegExp(
      r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$',
    );
    if (!emailRegex.hasMatch(text)) {
      return 'Please enter a valid email.';
    }
    return null;
  }

  String? Function(String?) _validateRequired(String label) {
    return (value) {
      if ((value?.trim() ?? '').isEmpty) {
        return '$label is required.';
      }
      return null;
    };
  }

  String? _validatePhone(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return 'Phone is required.';
    }
    if (!isValidPhilippinePhone(text)) {
      return 'Please enter a valid PH mobile number.';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    final text = value ?? '';
    if (text.isEmpty) {
      return 'Password is required.';
    }
    if (text.length < 6) {
      return 'Password must be at least 6 characters.';
    }
    return null;
  }

  String? _validateLicense(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return 'License is required.';
    }
    if (text.length < 4) {
      return 'License must be at least 4 characters.';
    }
    return null;
  }

  String? _validateLatitude(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return 'Latitude is required.';
    }
    final parsed = double.tryParse(text);
    if (parsed == null || parsed < -90 || parsed > 90) {
      return 'Latitude must be between -90 and 90.';
    }
    return null;
  }

  String? _validateLongitude(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return 'Longitude is required.';
    }
    final parsed = double.tryParse(text);
    if (parsed == null || parsed < -180 || parsed > 180) {
      return 'Longitude must be between -180 and 180.';
    }
    return null;
  }

  static double? _tryParseDouble(String value) {
    final text = value.trim();
    if (text.isEmpty) {
      return null;
    }
    return double.tryParse(text);
  }
}

class _AuthTextField extends StatefulWidget {
  const _AuthTextField({
    required this.controller,
    required this.label,
    this.keyboardType,
    this.obscureText = false,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final bool obscureText;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;

  @override
  State<_AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<_AuthTextField> {
  late bool _isObscured;

  @override
  void initState() {
    super.initState();
    _isObscured = widget.obscureText;
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      keyboardType: widget.keyboardType,
      obscureText: _isObscured,
      textCapitalization: widget.textCapitalization,
      inputFormatters: widget.inputFormatters,
      decoration: InputDecoration(
        labelText: widget.label,
        labelStyle: TextStyle(
          color: AppColors.primaryColor.withValues(alpha: 0.72),
          fontWeight: FontWeight.w400,
        ),
        floatingLabelStyle: const TextStyle(
          color: AppColors.primaryColor,
          fontWeight: FontWeight.w500,
        ),
        hintStyle: TextStyle(
          color: AppColors.primaryColor.withValues(alpha: 0.72),
          fontWeight: FontWeight.w400,
        ),
        prefixIconColor: AppColors.primaryColor,
        suffixIconColor: AppColors.primaryColor,
        filled: true,
        fillColor: AppColors.primarySurface,
        suffixIcon: widget.obscureText
            ? IconButton(
                onPressed: () {
                  setState(() => _isObscured = !_isObscured);
                },
                icon: Icon(
                  _isObscured
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: AppColors.primaryColor,
                ),
              )
            : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.primaryBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.primaryBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.primaryColor),
        ),
      ),
    );
  }
}

class _AuthDropdownField extends StatelessWidget {
  const _AuthDropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.itemLabelBuilder,
  });

  final String label;
  final String? value;
  final List<String> items;
  final ValueChanged<String?> onChanged;
  final String Function(String value)? itemLabelBuilder;

  @override
  Widget build(BuildContext context) {
    return AdminDropdownFormField<String>(
      initialValue: value,
      iconEnabledColor: AppColors.primaryColor,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: AppColors.primaryColor.withValues(alpha: 0.72),
          fontWeight: FontWeight.w400,
        ),
        floatingLabelStyle: const TextStyle(
          color: AppColors.primaryColor,
          fontWeight: FontWeight.w500,
        ),
        hintStyle: TextStyle(
          color: AppColors.primaryColor.withValues(alpha: 0.72),
          fontWeight: FontWeight.w400,
        ),
        filled: true,
        fillColor: AppColors.primarySurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.primaryBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.primaryBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.primaryColor),
        ),
      ),
      items: items
          .map(
            (role) => DropdownMenuItem<String>(
              value: role,
              child: Text(
                itemLabelBuilder?.call(role) ?? humanizeDropdownValue(role),
                style: adminDropdownDisplayTextStyle,
              ),
            ),
          )
          .toList(),
    );
  }
}
