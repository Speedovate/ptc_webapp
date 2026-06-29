import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:stacked/stacked.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/requests/auth.request.dart';
import 'package:webapp/models/vehicle_catalog_item.dart';
import 'package:webapp/requests/vehicle.request.dart';
import 'package:webapp/repositories/interfaces/auth_repository.dart';
import 'package:webapp/utils/functions.dart';
import 'package:webapp/view_models/auth/auth.vm.dart';
import 'package:webapp/widgets/admin_form_controls.dart';
import 'package:webapp/widgets/shared/app_mouse_pressable.dart';
import 'package:webapp/widgets/shared/app_page_loading.dart';
import 'package:webapp/widgets/shared/app_snackbar.dart';

class AuthView extends StatefulWidget {
  const AuthView({super.key, required this.onAuthenticated});

  final ValueChanged<UserModel> onAuthenticated;

  @override
  State<AuthView> createState() => _AuthViewState();
}

class _RegisterUploadResult {
  const _RegisterUploadResult({required this.user, this.errorMessage});

  final UserModel user;
  final String? errorMessage;
}

class _AuthViewState extends State<AuthView> {
  static const double _authFieldSpacing = 6;
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
  final _loginIdentifierFocusNode = FocusNode();
  final _loginPasswordFocusNode = FocusNode();
  final _registerEmailFocusNode = FocusNode();
  final _registerNameFocusNode = FocusNode();
  final _registerPhoneFocusNode = FocusNode();
  final _registerLatFocusNode = FocusNode();
  final _registerLngFocusNode = FocusNode();
  final _registerPasswordFocusNode = FocusNode();
  final AuthRequest _authRequest = AuthRequest.instance;

  String? _registerRole;
  String? _registerVehicleTypeId;
  bool _isLoginMode = true;
  bool _isLoadingVehicleTypes = true;
  bool _isSubmittingAuthFlow = false;
  String _authFlowLoadingMessage = 'Loading, please wait ...';
  List<VehicleCatalogItem> _vehicleTypes = const [];
  _PendingAuthImageUpload? _registerProfilePhotoUpload;
  _PendingAuthImageUpload? _registerLicensePhotoUpload;

  static const _roleOptions = ['client', 'driver', 'helper', 'dispatcher'];

  @override
  void initState() {
    super.initState();
    _loadVehicleTypes();
  }

  Future<void> _showPostRegisterUploadIssue(String message) async {
    AppSnackbar.showError(context, message);
    await Future<void>.delayed(const Duration(milliseconds: 1800));
  }

  Future<void> _showAuthFlowStage(String message) async {
    _setAuthFlowLoading(true, message: message);
    // Give Flutter one frame to paint/update the overlay before the next step.
    await Future<void>.delayed(const Duration(milliseconds: 16));
  }

  void _setAuthFlowLoading(bool isLoading, {String? message}) {
    if (!mounted) {
      return;
    }
    setState(() {
      _isSubmittingAuthFlow = isLoading;
      if (message != null) {
        _authFlowLoadingMessage = message;
      } else if (!isLoading) {
        _authFlowLoadingMessage = 'Loading, please wait ...';
      }
    });
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
    _loginIdentifierFocusNode.dispose();
    _loginPasswordFocusNode.dispose();
    _registerEmailFocusNode.dispose();
    _registerNameFocusNode.dispose();
    _registerPhoneFocusNode.dispose();
    _registerLatFocusNode.dispose();
    _registerLngFocusNode.dispose();
    _registerPasswordFocusNode.dispose();
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
    _registerProfilePhotoUpload = null;
    _registerLicensePhotoUpload = null;
  }

  void _switchAuthMode() {
    setState(() {
      _isLoginMode = !_isLoginMode;
      _resetLoginFields();
      _resetRegisterFields();
    });
  }

  void _focusNext(FocusNode focusNode) {
    if (!mounted) {
      return;
    }
    FocusScope.of(context).requestFocus(focusNode);
  }

  void _unfocusCurrentField() {
    final currentFocus = FocusScope.of(context);
    if (!currentFocus.hasPrimaryFocus) {
      currentFocus.unfocus();
    }
  }

  Future<void> _showPendingApprovalDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text(
            'Account Has Been Created',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: const Text(
            'Your account was created successfully. Please contact your admin so they can activate your driver or helper account.',
            style: TextStyle(color: AppColors.textPrimary, height: 1.4),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text('Okay'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder<AuthViewModel>.reactive(
      viewModelBuilder: AuthViewModel.new,
      builder: (context, vm, child) {
        final isBusy = vm.isBusy;
        final isAuthBusy = isBusy || _isSubmittingAuthFlow;
        return Scaffold(
          backgroundColor: AppColors.primaryColor,
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 700;

                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(24, isCompact ? 20 : 24, 24, 24),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - (isCompact ? 44 : 48),
                    ),
                    child: Align(
                      alignment: Alignment.center,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 460),
                        child: Stack(
                          children: [
                            Container(
                              padding: const EdgeInsets.fromLTRB(
                                28,
                                26,
                                28,
                                28,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: AppColors.primaryBorder,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x120E0A1F),
                                    blurRadius: 32,
                                    offset: Offset(0, 18),
                                  ),
                                ],
                              ),
                              child: Opacity(
                                opacity: isAuthBusy ? 0.5 : 1,
                                child: IgnorePointer(
                                  ignoring: isAuthBusy,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          Container(
                                            width: 56,
                                            height: 56,
                                            decoration: BoxDecoration(
                                              color: AppColors.primaryColor,
                                              borderRadius: BorderRadius.all(
                                                Radius.circular(18),
                                              ),
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
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                const Text(
                                                  'Paltranco',
                                                  style: TextStyle(
                                                    color:
                                                        AppColors.primaryColor,
                                                    fontSize: 25,
                                                    fontWeight: FontWeight.w800,
                                                    height: 1.2,
                                                  ),
                                                ),
                                                const Text(
                                                  'Digital Platform',
                                                  style: TextStyle(
                                                    color:
                                                        AppColors.textPrimary,
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w500,
                                                    height: 1.2,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (!_isLoginMode) ...[
                                            const SizedBox(width: 14),
                                            _AuthHeaderCameraButton(
                                              hasSelection:
                                                  _registerProfilePhotoUpload !=
                                                  null,
                                              previewBytes:
                                                  _registerProfilePhotoUpload
                                                      ?.bytes,
                                              onTap: _pickRegisterProfilePhoto,
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 24),
                                      AnimatedSwitcher(
                                        duration: const Duration(
                                          milliseconds: 220,
                                        ),
                                        switchInCurve: Curves.easeOut,
                                        switchOutCurve: Curves.easeIn,
                                        child: _isLoginMode
                                            ? Form(
                                                key: _loginFormKey,
                                                child: Column(
                                                  key: const ValueKey(
                                                    'login_form',
                                                  ),
                                                  children: [
                                                    _AuthTextField(
                                                      controller:
                                                          _loginEmailController,
                                                      focusNode:
                                                          _loginIdentifierFocusNode,
                                                      label: 'Email or Number',
                                                      keyboardType:
                                                          TextInputType
                                                              .emailAddress,
                                                      textInputAction:
                                                          TextInputAction.next,
                                                      onSubmitted: (_) =>
                                                          _focusNext(
                                                            _loginPasswordFocusNode,
                                                          ),
                                                    ),
                                                    const SizedBox(
                                                      height: _authFieldSpacing,
                                                    ),
                                                    _AuthTextField(
                                                      controller:
                                                          _loginPasswordController,
                                                      focusNode:
                                                          _loginPasswordFocusNode,
                                                      label: 'Password',
                                                      obscureText: true,
                                                      textInputAction:
                                                          TextInputAction.done,
                                                      onSubmitted: (_) {
                                                        _unfocusCurrentField();
                                                        _submit(vm);
                                                      },
                                                    ),
                                                  ],
                                                ),
                                              )
                                            : _isLoadingVehicleTypes
                                            ? const SizedBox(
                                                key: ValueKey(
                                                  'register_loading',
                                                ),
                                                height: 220,
                                                child: AppPageLoading(
                                                  message:
                                                      'Loading vehicle types ...',
                                                  compact: true,
                                                  padding: EdgeInsets.zero,
                                                ),
                                              )
                                            : Form(
                                                key: _registerFormKey,
                                                child: Column(
                                                  key: const ValueKey(
                                                    'register_form',
                                                  ),
                                                  children: [
                                                    _AuthDropdownField(
                                                      label: 'Role',
                                                      value: _registerRole,
                                                      items: _roleOptions,
                                                      onChanged: (value) {
                                                        setState(() {
                                                          _registerRole = value;
                                                          if (value !=
                                                              'driver') {
                                                            _registerVehicleTypeId =
                                                                null;
                                                          }
                                                        });
                                                      },
                                                    ),
                                                    if (_registerRole ==
                                                        'driver') ...[
                                                      const SizedBox(
                                                        height:
                                                            _authFieldSpacing,
                                                      ),
                                                      _AuthDropdownField(
                                                        label: 'Vehicle Type',
                                                        value:
                                                            _registerVehicleTypeId,
                                                        items: _vehicleTypes
                                                            .map(
                                                              (item) =>
                                                                  item.id ?? '',
                                                            )
                                                            .where(
                                                              (value) => value
                                                                  .isNotEmpty,
                                                            )
                                                            .toList(),
                                                        itemLabelBuilder: (value) {
                                                          final match =
                                                              _vehicleTypes.where(
                                                                (item) =>
                                                                    item.id ==
                                                                    value,
                                                              );
                                                          if (match.isEmpty) {
                                                            return 'Selected vehicle type';
                                                          }
                                                          final item =
                                                              match.first;
                                                          final name =
                                                              item.name
                                                                  ?.trim() ??
                                                              '';
                                                          final slug =
                                                              item.slug
                                                                  ?.trim() ??
                                                              '';
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
                                                            () =>
                                                                _registerVehicleTypeId =
                                                                    value,
                                                          );
                                                        },
                                                      ),
                                                    ],
                                                    const SizedBox(
                                                      height: _authFieldSpacing,
                                                    ),
                                                    _AuthTextField(
                                                      controller:
                                                          _registerEmailController,
                                                      focusNode:
                                                          _registerEmailFocusNode,
                                                      label: 'Email',
                                                      keyboardType:
                                                          TextInputType
                                                              .emailAddress,
                                                      textInputAction:
                                                          TextInputAction.next,
                                                      onSubmitted: (_) =>
                                                          _focusNext(
                                                            _registerNameFocusNode,
                                                          ),
                                                    ),
                                                    const SizedBox(
                                                      height: _authFieldSpacing,
                                                    ),
                                                    _AuthTextField(
                                                      controller:
                                                          _registerNameController,
                                                      focusNode:
                                                          _registerNameFocusNode,
                                                      label: 'Name',
                                                      textCapitalization:
                                                          TextCapitalization
                                                              .words,
                                                      inputFormatters: const [
                                                        NameCaseTextInputFormatter(),
                                                      ],
                                                      textInputAction:
                                                          TextInputAction.next,
                                                      onSubmitted: (_) =>
                                                          _focusNext(
                                                            _registerPhoneFocusNode,
                                                          ),
                                                    ),
                                                    const SizedBox(
                                                      height: _authFieldSpacing,
                                                    ),
                                                    _AuthTextField(
                                                      controller:
                                                          _registerPhoneController,
                                                      focusNode:
                                                          _registerPhoneFocusNode,
                                                      label: 'Phone',
                                                      keyboardType:
                                                          TextInputType.phone,
                                                      inputFormatters: const [
                                                        PhilippinesPhoneInputFormatter(),
                                                      ],
                                                      textInputAction:
                                                          TextInputAction.next,
                                                      onSubmitted: (_) => _focusNext(
                                                        _registerRole ==
                                                                'driver'
                                                            ? _registerLatFocusNode
                                                            : _registerPasswordFocusNode,
                                                      ),
                                                    ),
                                                    if (_registerRole ==
                                                        'driver') ...[
                                                      const SizedBox(
                                                        height:
                                                            _authFieldSpacing,
                                                      ),
                                                      _AuthActionField(
                                                        label: 'License',
                                                        valueText:
                                                            _registerLicenseController
                                                                .text,
                                                        onTap:
                                                            _pickRegisterLicensePhoto,
                                                      ),
                                                      const SizedBox(
                                                        height:
                                                            _authFieldSpacing,
                                                      ),
                                                      _AuthTextField(
                                                        controller:
                                                            _registerLatController,
                                                        focusNode:
                                                            _registerLatFocusNode,
                                                        label: 'Latitude',
                                                        keyboardType:
                                                            const TextInputType.numberWithOptions(
                                                              decimal: true,
                                                              signed: true,
                                                            ),
                                                        textInputAction:
                                                            TextInputAction
                                                                .next,
                                                        onSubmitted: (_) =>
                                                            _focusNext(
                                                              _registerLngFocusNode,
                                                            ),
                                                      ),
                                                      const SizedBox(
                                                        height:
                                                            _authFieldSpacing,
                                                      ),
                                                      _AuthTextField(
                                                        controller:
                                                            _registerLngController,
                                                        focusNode:
                                                            _registerLngFocusNode,
                                                        label: 'Longitude',
                                                        keyboardType:
                                                            const TextInputType.numberWithOptions(
                                                              decimal: true,
                                                              signed: true,
                                                            ),
                                                        textInputAction:
                                                            TextInputAction
                                                                .next,
                                                        onSubmitted: (_) =>
                                                            _focusNext(
                                                              _registerPasswordFocusNode,
                                                            ),
                                                      ),
                                                    ],
                                                    const SizedBox(
                                                      height: _authFieldSpacing,
                                                    ),
                                                    _AuthTextField(
                                                      controller:
                                                          _registerPasswordController,
                                                      focusNode:
                                                          _registerPasswordFocusNode,
                                                      label: 'Password',
                                                      obscureText: true,
                                                      textInputAction:
                                                          TextInputAction.done,
                                                      onSubmitted: (_) {
                                                        _unfocusCurrentField();
                                                        _submit(vm);
                                                      },
                                                    ),
                                                  ],
                                                ),
                                              ),
                                      ),
                                      const SizedBox(height: 16),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: SizedBox(
                                              height: 52,
                                              child: OutlinedButton(
                                                onPressed: isAuthBusy
                                                    ? null
                                                    : _switchAuthMode,
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor:
                                                      AppColors.primaryColor,
                                                  side: const BorderSide(
                                                    color:
                                                        AppColors.primaryBorder,
                                                  ),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          18,
                                                        ),
                                                  ),
                                                ),
                                                child: Text(
                                                  _isLoginMode
                                                      ? 'Sign Up'
                                                      : 'Sign In',
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
                                                onPressed: isAuthBusy
                                                    ? null
                                                    : () => _submit(vm),
                                                style: FilledButton.styleFrom(
                                                  backgroundColor:
                                                      AppColors.primaryColor,
                                                  foregroundColor: Colors.white,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          18,
                                                        ),
                                                  ),
                                                ),
                                                child: isAuthBusy
                                                    ? const SizedBox(
                                                        width: 22,
                                                        height: 22,
                                                        child:
                                                            CircularProgressIndicator(
                                                              strokeWidth: 2.4,
                                                              color:
                                                                  Colors.white,
                                                            ),
                                                      )
                                                    : Text(
                                                        _isLoginMode
                                                            ? 'Sign In'
                                                            : 'Sign Up',
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.w700,
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
                            if (isAuthBusy)
                              Positioned.fill(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.72),
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                  child: AppPageLoading(
                                    message: _authFlowLoadingMessage,
                                    compact: true,
                                    padding: const EdgeInsets.all(24),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _submit(AuthViewModel vm) async {
    try {
      if (_isLoginMode) {
        final validationMessage = _loginValidationMessage();
        if (validationMessage != null) {
          AppSnackbar.showError(context, validationMessage);
          return;
        }
        await _showAuthFlowStage('Loading, please wait ...');
        if (!mounted) {
          return;
        }
        await _showAuthFlowStage('Signing you in ...');
        final user = await vm.login(
          identifier: _loginEmailController.text.trim(),
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
      await _showAuthFlowStage('Loading, please wait ...');
      if (!mounted) {
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
      await _showAuthFlowStage('Creating your account ...');
      final user = await vm.register(
        _registerRole == 'driver'
            ? DriverModel(
                role: _registerRole,
                email: _registerEmailController.text.trim(),
                name: _registerNameController.text.trim(),
                phone: normalizedPhone,
                password: _registerPasswordController.text,
                license: null,
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
        await _showAuthFlowStage('Uploading your photo ...');
        final uploadResult = await _completeRegisterImageUploads(user);
        final uploadedUser = uploadResult.user;
        if (!mounted) {
          return;
        }
        if (uploadResult.errorMessage?.trim().isNotEmpty == true) {
          _setAuthFlowLoading(false);
          await _showPostRegisterUploadIssue(uploadResult.errorMessage!);
          if (!mounted) {
            return;
          }
          await _showAuthFlowStage('Signing you in ...');
        }
        if (uploadedUser.isActive ?? false) {
          await _showAuthFlowStage('Signing you in ...');
          final authenticatedUser = await vm.login(
            identifier: _registerEmailController.text.trim(),
            password: _registerPasswordController.text,
          );
          if (!mounted) {
            return;
          }
          if (authenticatedUser != null) {
            widget.onAuthenticated(authenticatedUser);
          } else {
            widget.onAuthenticated(uploadedUser);
          }
        } else {
          if (!mounted) {
            return;
          }
          _setAuthFlowLoading(false);
          await _showPendingApprovalDialog();
          if (!mounted) {
            return;
          }
          setState(() {
            _isLoginMode = true;
            _resetLoginFields();
            _resetRegisterFields();
          });
        }
      } else if (mounted && vm.errorMessage?.isNotEmpty == true) {
        AppSnackbar.showError(context, vm.errorMessage!);
      }
    } finally {
      _setAuthFlowLoading(false);
    }
  }

  String? _loginValidationMessage() {
    return _validateLoginIdentifier(_loginEmailController.text) ??
        _validatePassword(_loginPasswordController.text);
  }

  String? _validateLoginIdentifier(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return 'Email or mobile number is required.';
    }
    if (text.contains('@')) {
      return _validateEmail(text);
    }
    if (!isValidPhilippinePhone(text)) {
      return 'Please enter a valid email or PH mobile number.';
    }
    return null;
  }

  String? _registerValidationMessage() {
    return _validateRegisterProfilePhoto() ??
        _validateRequired('Role')(_registerRole) ??
        (_registerRole == 'driver'
            ? _validateRequired('Vehicle type')(_registerVehicleTypeId)
            : null) ??
        _validateEmail(_registerEmailController.text) ??
        _validateRequired('Name')(_registerNameController.text) ??
        _validatePhone(_registerPhoneController.text) ??
        (_registerRole == 'driver' ? _validateLicensePhoto() : null) ??
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
    return null;
  }

  String? _validateLicensePhoto() {
    if (_registerLicensePhotoUpload != null) {
      return null;
    }
    return _validateLicense(_registerLicenseController.text);
  }

  String? _validateRegisterProfilePhoto() {
    if (_registerProfilePhotoUpload != null) {
      return null;
    }
    return 'Profile photo is required.';
  }

  Future<void> _pickRegisterProfilePhoto() async {
    final upload = await _pickAuthImageUpload();
    if (upload == null || !mounted) {
      return;
    }
    setState(() {
      _registerProfilePhotoUpload = upload;
    });
  }

  Future<void> _pickRegisterLicensePhoto() async {
    final upload = await _pickAuthImageUpload();
    if (upload == null || !mounted) {
      return;
    }
    setState(() {
      _registerLicensePhotoUpload = upload;
      _registerLicenseController.text = upload.fileName;
    });
  }

  Future<_PendingAuthImageUpload?> _pickAuthImageUpload() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = result?.files.singleOrNull;
    final bytes = file?.bytes;
    if (file == null || bytes == null) {
      return null;
    }
    return _PendingAuthImageUpload(
      bytes: bytes,
      fileName: file.name,
      size: file.size,
      mimeType: _resolvedMimeType(file.extension),
    );
  }

  Future<_RegisterUploadResult> _completeRegisterImageUploads(
    UserModel user,
  ) async {
    var updatedUser = user;
    String? errorMessage;

    try {
      final profileUpload = _registerProfilePhotoUpload;
      if (profileUpload != null && (updatedUser.id?.isNotEmpty == true)) {
        updatedUser = await _authRequest.saveUserPhoto(
          userId: updatedUser.id!,
          bytes: profileUpload.bytes,
          fileName: profileUpload.fileName,
          mimeType: profileUpload.mimeType,
          size: profileUpload.size,
        );
      }

      final licenseUpload = _registerLicensePhotoUpload;
      if (licenseUpload != null &&
          updatedUser.role == 'driver' &&
          (updatedUser.id?.isNotEmpty == true)) {
        updatedUser = await _authRequest.saveDriverLicensePhoto(
          userId: updatedUser.id!,
          bytes: licenseUpload.bytes,
          fileName: licenseUpload.fileName,
          mimeType: licenseUpload.mimeType,
          size: licenseUpload.size,
        );
      }
    } on AuthFailure catch (error) {
      errorMessage = error.message;
    } catch (error) {
      errorMessage = userFacingErrorMessage(
        error,
        fallback:
            'Account created, but an image upload could not be completed.',
      );
    }

    return _RegisterUploadResult(user: updatedUser, errorMessage: errorMessage);
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

  String? _resolvedMimeType(String? extension) {
    switch ((extension ?? '').toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'bmp':
        return 'image/bmp';
      default:
        return 'image/jpeg';
    }
  }
}

class _PendingAuthImageUpload {
  const _PendingAuthImageUpload({
    required this.bytes,
    required this.fileName,
    required this.size,
    this.mimeType,
  });

  final Uint8List bytes;
  final String fileName;
  final int size;
  final String? mimeType;
}

class _AuthTextField extends StatefulWidget {
  const _AuthTextField({
    required this.controller,
    this.focusNode,
    required this.label,
    this.keyboardType,
    this.obscureText = false,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.textInputAction,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String label;
  final TextInputType? keyboardType;
  final bool obscureText;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<_AuthTextField> {
  late bool _isObscured;
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _isObscured = widget.obscureText;
  }

  @override
  Widget build(BuildContext context) {
    final activeFillColor = appFieldInteractiveFillColor(context);
    return MouseRegion(
      cursor: SystemMouseCursors.text,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() {
        _isHovered = false;
        _isPressed = false;
      }),
      child: Listener(
        onPointerDown: (_) => setState(() => _isPressed = true),
        onPointerUp: (_) {
          if (_isPressed) {
            setState(() => _isPressed = false);
          }
        },
        onPointerCancel: (_) {
          if (_isPressed) {
            setState(() => _isPressed = false);
          }
        },
        child: TextFormField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          keyboardType: widget.keyboardType,
          obscureText: _isObscured,
          textCapitalization: widget.textCapitalization,
          inputFormatters: widget.inputFormatters,
          textInputAction: widget.textInputAction,
          onFieldSubmitted: widget.onSubmitted,
          style: adminFieldValueTextStyle,
          decoration:
              adminFormInputDecoration(
                widget.label,
                radius: 18,
                minHeight: adminModalFieldMinHeight,
              ).copyWith(
                fillColor: _isHovered || _isPressed
                    ? activeFillColor
                    : AppColors.primarySurface,
                suffixIcon: widget.obscureText
                    ? Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: IconButton(
                          onPressed: () {
                            setState(() => _isObscured = !_isObscured);
                          },
                          icon: Icon(
                            _isObscured
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            color: AppColors.primaryColor,
                          ),
                        ),
                      )
                    : null,
              ),
        ),
      ),
    );
  }
}

class _AuthActionField extends StatefulWidget {
  const _AuthActionField({
    required this.label,
    required this.valueText,
    required this.onTap,
  });

  final String label;
  final String valueText;
  final VoidCallback onTap;

  @override
  State<_AuthActionField> createState() => _AuthActionFieldState();
}

class _AuthActionFieldState extends State<_AuthActionField> {
  late final TextEditingController _controller;
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.valueText);
  }

  @override
  void didUpdateWidget(covariant _AuthActionField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.text != widget.valueText) {
      _controller.value = _controller.value.copyWith(
        text: widget.valueText,
        selection: TextSelection.collapsed(offset: widget.valueText.length),
        composing: TextRange.empty,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hoveredFillColor = appFieldInteractiveFillColor(context);
    final decoration =
        adminFormInputDecoration(
          widget.label,
          radius: 18,
          minHeight: adminModalFieldMinHeight,
        ).copyWith(
          suffixIcon: const Padding(
            padding: EdgeInsets.only(right: 6),
            child: Icon(Icons.upload_rounded, color: AppColors.primaryColor),
          ),
          fillColor: _isPressed || _isHovered
              ? hoveredFillColor
              : AppColors.primarySurface,
        );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() {
        _isHovered = false;
        _isPressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapCancel: () => setState(() => _isPressed = false),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTap: widget.onTap,
        child: IgnorePointer(
          child: TextFormField(
            controller: _controller,
            readOnly: true,
            showCursor: false,
            enableInteractiveSelection: false,
            style: adminFieldValueTextStyle,
            decoration: decoration,
          ),
        ),
      ),
    );
  }
}

class _AuthHeaderCameraButton extends StatelessWidget {
  const _AuthHeaderCameraButton({
    required this.hasSelection,
    this.previewBytes,
    required this.onTap,
  });

  final bool hasSelection;
  final Uint8List? previewBytes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasPreview = previewBytes != null && previewBytes!.isNotEmpty;
    return AppMousePressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Builder(
        builder: (context) => Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: hasSelection
                ? (appPressableActive(context)
                      ? const Color(0xFFE0D4FF)
                      : const Color(0xFFF1EBFF))
                : appPressableActive(context)
                ? AppColors.primarySurfaceAlt.withValues(alpha: 0.34)
                : Colors.white,
            border: Border.all(
              color: hasSelection
                  ? AppColors.primaryColor
                  : AppColors.primaryBorder,
            ),
          ),
          child: ClipOval(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (hasPreview)
                  Image.memory(previewBytes!, fit: BoxFit.cover)
                else
                  const SizedBox.shrink(),
                if (!hasPreview)
                  const Icon(
                    Icons.photo_camera_rounded,
                    color: AppColors.primaryColor,
                    size: 22,
                  ),
              ],
            ),
          ),
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
      decoration: adminFormInputDecoration(
        label,
        radius: 18,
        minHeight: adminModalFieldMinHeight,
      ),
      style: adminFieldValueTextStyle,
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
