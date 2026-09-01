import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:stacked/stacked.dart';
import 'package:webapp/constants/app_colors.dart';
import 'package:webapp/models/dispatcher_access_config.dart';
import 'package:webapp/models/user.dart';
import 'package:webapp/requests/auth.request.dart';
import 'package:webapp/models/vehicle_catalog_item.dart';
import 'package:webapp/requests/vehicle.request.dart';
import 'package:webapp/repositories/interfaces/auth_repository.dart';
import 'package:webapp/services/auth_camera_service.dart';
import 'package:webapp/services/auth_image_picker_service.dart';
import 'package:webapp/services/local_form_draft_service.dart';
import 'package:webapp/services/role_access_service.dart';
import 'package:webapp/utils/functions.dart';
import 'package:webapp/view_models/auth/auth.vm.dart';
import 'package:webapp/widgets/admin_form_controls.dart';
import 'package:webapp/widgets/shared/app_modal_guard.dart';
import 'package:webapp/widgets/shared/app_mouse_pressable.dart';
import 'package:webapp/widgets/shared/app_snackbar.dart';

class AuthView extends StatefulWidget {
  const AuthView({super.key, required this.onAuthenticated});

  final Future<void> Function(UserModel) onAuthenticated;

  @override
  State<AuthView> createState() => _AuthViewState();
}

class _RegisterUploadResult {
  const _RegisterUploadResult({required this.user, this.errorMessage});

  final UserModel user;
  final String? errorMessage;
}

class _AuthViewState extends State<AuthView> with WidgetsBindingObserver {
  static const double _authFieldSpacing = 6;
  static const String _loginDraftStorageKey = 'auth_login_draft_v1';
  static const String _registerDraftStorageKey = 'auth_register_draft_v1';
  static const String _legacyAuthDraftStorageKey = 'auth_form_draft_v1';
  final _loginFormKey = GlobalKey<FormState>();
  final _registerFormKey = GlobalKey<FormState>();

  final _loginEmailController = TextEditingController();
  final _loginPasswordController = TextEditingController();
  final _registerEmailController = TextEditingController();
  final _registerNameController = TextEditingController();
  final _registerPhoneController = TextEditingController();
  final _registerLicenseController = TextEditingController();
  final _registerPasswordController = TextEditingController();
  final _loginIdentifierFocusNode = FocusNode();
  final _loginPasswordFocusNode = FocusNode();
  final _registerEmailFocusNode = FocusNode();
  final _registerNameFocusNode = FocusNode();
  final _registerPhoneFocusNode = FocusNode();
  final _registerPasswordFocusNode = FocusNode();
  final AuthRequest _authRequest = AuthRequest.instance;
  final LocalFormDraftService _draftService = LocalFormDraftService.instance;

  String? _registerRole;
  String? _registerVehicleTypeId;
  bool _isLoginMode = true;
  bool _isLoadingVehicleTypes = true;
  bool _isSubmittingAuthFlow = false;
  String _authFlowLoadingMessage = 'Loading, please wait ...';
  List<VehicleCatalogItem> _vehicleTypes = const [];
  _PendingAuthImageUpload? _registerProfilePhotoUpload;
  _PendingAuthImageUpload? _registerLicensePhotoUpload;
  AuthCameraSession? _activeCameraSession;
  bool _isHydratingDraft = false;
  bool _isRestoringDraft = true;
  bool _suppressDraftPersistence = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _attachDraftListeners();
    unawaited(_restoreDraft());
    _loadVehicleTypes();
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
    } catch (_) {
      // Registration remains available when the optional driver catalog is
      // temporarily unavailable during Firebase startup.
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
    WidgetsBinding.instance.removeObserver(this);
    if (!_suppressDraftPersistence) {
      unawaited(_persistDraftImmediately());
    }
    final activeCameraSession = _activeCameraSession;
    _activeCameraSession = null;
    if (activeCameraSession != null) {
      unawaited(activeCameraSession.dispose());
    }
    _loginEmailController.dispose();
    _loginPasswordController.dispose();
    _registerEmailController.dispose();
    _registerNameController.dispose();
    _registerPhoneController.dispose();
    _registerLicenseController.dispose();
    _registerPasswordController.dispose();
    _loginIdentifierFocusNode.dispose();
    _loginPasswordFocusNode.dispose();
    _registerEmailFocusNode.dispose();
    _registerNameFocusNode.dispose();
    _registerPhoneFocusNode.dispose();
    _registerPasswordFocusNode.dispose();
    _detachDraftListeners();
    super.dispose();
  }

  @override
  void reassemble() {
    final activeCameraSession = _activeCameraSession;
    _activeCameraSession = null;
    if (activeCameraSession != null) {
      unawaited(activeCameraSession.dispose());
    }
    super.reassemble();
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
    _registerPasswordController.clear();
    _registerRole = null;
    _registerVehicleTypeId = null;
    _registerProfilePhotoUpload = null;
    _registerLicensePhotoUpload = null;
  }

  void _switchAuthMode() {
    setState(() {
      _isLoginMode = !_isLoginMode;
    });
    unawaited(_persistDraftImmediately());
  }

  void _attachDraftListeners() {
    _loginEmailController.addListener(_scheduleDraftPersist);
    _loginPasswordController.addListener(_scheduleDraftPersist);
    _registerEmailController.addListener(_scheduleDraftPersist);
    _registerNameController.addListener(_scheduleDraftPersist);
    _registerPhoneController.addListener(_scheduleDraftPersist);
    _registerLicenseController.addListener(_scheduleDraftPersist);
    _registerPasswordController.addListener(_scheduleDraftPersist);
  }

  void _detachDraftListeners() {
    _loginEmailController.removeListener(_scheduleDraftPersist);
    _loginPasswordController.removeListener(_scheduleDraftPersist);
    _registerEmailController.removeListener(_scheduleDraftPersist);
    _registerNameController.removeListener(_scheduleDraftPersist);
    _registerPhoneController.removeListener(_scheduleDraftPersist);
    _registerLicenseController.removeListener(_scheduleDraftPersist);
    _registerPasswordController.removeListener(_scheduleDraftPersist);
  }

  void _scheduleDraftPersist() {
    unawaited(_persistDraftImmediately());
  }

  Map<String, dynamic> _buildLoginDraftPayload() {
    return <String, dynamic>{
      'is_login_mode': _isLoginMode,
      'identifier': _loginEmailController.text,
      'password': _loginPasswordController.text,
    };
  }

  Map<String, dynamic> _buildRegisterDraftPayload() {
    return <String, dynamic>{
      'email': _registerEmailController.text,
      'name': _registerNameController.text,
      'phone': _registerPhoneController.text,
      'license_text': _registerLicenseController.text,
      'password': _registerPasswordController.text,
      'role': _registerRole,
      'vehicle_type_id': _registerVehicleTypeId,
      'profile_photo': _registerProfilePhotoUpload?.toMap(),
      'license_photo': _registerLicensePhotoUpload?.toMap(),
    };
  }

  Future<void> _restoreDraft() async {
    try {
      final loginDraft =
          await _draftService.readMap(_loginDraftStorageKey) ??
          await _restoreLegacyLoginDraft();
      final registerDraft =
          await _draftService.readMap(_registerDraftStorageKey) ??
          await _restoreLegacyRegisterDraft();
      _isHydratingDraft = true;
      setState(() {
        _isLoginMode = loginDraft?['is_login_mode'] != false;
        _loginEmailController.text =
            loginDraft?['identifier']?.toString() ?? '';
        _loginPasswordController.text =
            loginDraft?['password']?.toString() ?? '';
        _registerRole = registerDraft?['role']?.toString();
        _registerVehicleTypeId = registerDraft?['vehicle_type_id']?.toString();
        _registerEmailController.text =
            registerDraft?['email']?.toString() ?? '';
        _registerNameController.text = registerDraft?['name']?.toString() ?? '';
        _registerPhoneController.text =
            registerDraft?['phone']?.toString() ?? '';
        _registerLicenseController.text =
            registerDraft?['license_text']?.toString() ?? '';
        _registerPasswordController.text =
            registerDraft?['password']?.toString() ?? '';
        _registerProfilePhotoUpload = _pendingUploadFromMap(
          registerDraft?['profile_photo'],
        );
        _registerLicensePhotoUpload = _pendingUploadFromMap(
          registerDraft?['license_photo'],
        );
      });
    } finally {
      _isHydratingDraft = false;
      _isRestoringDraft = false;
    }
  }

  Future<Map<String, dynamic>?> _restoreLegacyLoginDraft() async {
    final legacy = await _draftService.readMap(_legacyAuthDraftStorageKey);
    if (legacy == null || legacy.isEmpty) {
      return null;
    }
    final login = legacy['login'] is Map
        ? Map<String, dynamic>.from(legacy['login'] as Map)
        : const <String, dynamic>{};
    return <String, dynamic>{
      'is_login_mode': legacy['is_login_mode'] != false,
      'identifier': login['identifier']?.toString() ?? '',
      'password': login['password']?.toString() ?? '',
    };
  }

  Future<Map<String, dynamic>?> _restoreLegacyRegisterDraft() async {
    final legacy = await _draftService.readMap(_legacyAuthDraftStorageKey);
    if (legacy == null || legacy.isEmpty) {
      return null;
    }
    return legacy['register'] is Map
        ? Map<String, dynamic>.from(legacy['register'] as Map)
        : null;
  }

  Future<void> _persistDraftImmediately() async {
    if (_suppressDraftPersistence || _isHydratingDraft || _isRestoringDraft) {
      return;
    }
    await _draftService.writeMapNow(
      _loginDraftStorageKey,
      _buildLoginDraftPayload(),
    );
    await _draftService.writeMapNow(
      _registerDraftStorageKey,
      _buildRegisterDraftPayload(),
    );
  }

  Future<void> _clearDraft() async {
    _suppressDraftPersistence = true;
    await _draftService.remove(_loginDraftStorageKey);
    await _draftService.remove(_registerDraftStorageKey);
    await _draftService.remove(_legacyAuthDraftStorageKey);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      unawaited(_persistDraftImmediately());
    }
  }

  _PendingAuthImageUpload? _pendingUploadFromMap(dynamic value) {
    if (value is! Map) {
      return null;
    }
    final map = Map<String, dynamic>.from(value);
    final bytes = map['bytes'];
    if (bytes is! Uint8List || bytes.isEmpty) {
      return null;
    }
    return _PendingAuthImageUpload(
      bytes: bytes,
      fileName: map['file_name']?.toString() ?? 'photo',
      size: (map['size'] as num?)?.toInt() ?? bytes.length,
      mimeType: map['mime_type']?.toString(),
    );
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
    await showAppDialog<void>(
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
    final roleAccessService = RoleAccessService.instance;
    return AnimatedBuilder(
      animation: roleAccessService,
      builder: (context, _) {
        final registerRoleOptions =
            (roleAccessService.publicRegisterRoleKeys.isEmpty
                    ? builtInRoleKeys
                    : roleAccessService.publicRegisterRoleKeys)
                .where(
                  (role) =>
                      role == 'client' || role == 'driver' || role == 'helper',
                )
                .toList(growable: false);
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
                      padding: EdgeInsets.fromLTRB(
                        24,
                        isCompact ? 20 : 24,
                        24,
                        24,
                      ),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight:
                              constraints.maxHeight - (isCompact ? 44 : 48),
                        ),
                        child: Align(
                          alignment: Alignment.center,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 460),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(24),
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
                                      // BoxDecoration paints its border over the
                                      // child, so hide it while the solid loading
                                      // overlay is visible.
                                      border: isAuthBusy
                                          ? null
                                          : Border.all(
                                              color: AppColors.primaryBorder,
                                            ),
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
                                                    color:
                                                        AppColors.primaryColor,
                                                    borderRadius:
                                                        BorderRadius.all(
                                                          Radius.circular(18),
                                                        ),
                                                  ),
                                                  child: const Icon(
                                                    Icons
                                                        .local_shipping_rounded,
                                                    color: Colors.white,
                                                    size: 28,
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Column(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      const Text(
                                                        'Paltranco',
                                                        style: TextStyle(
                                                          color: AppColors
                                                              .primaryColor,
                                                          fontSize: 25,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          height: 1.2,
                                                        ),
                                                      ),
                                                      const Text(
                                                        'Digital Platform',
                                                        style: TextStyle(
                                                          color: AppColors
                                                              .textPrimary,
                                                          fontSize: 15,
                                                          fontWeight:
                                                              FontWeight.w500,
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
                                                    onTap:
                                                        _pickRegisterProfilePhoto,
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
                                                            label:
                                                                'Email or Phone',
                                                            keyboardType:
                                                                TextInputType
                                                                    .emailAddress,
                                                            inputFormatters: const [
                                                              EmailOrPhilippinesPhoneInputFormatter(),
                                                            ],
                                                            textInputAction:
                                                                TextInputAction
                                                                    .next,
                                                            onSubmitted: (_) =>
                                                                _focusNext(
                                                                  _loginPasswordFocusNode,
                                                                ),
                                                          ),
                                                          const SizedBox(
                                                            height:
                                                                _authFieldSpacing,
                                                          ),
                                                          _AuthTextField(
                                                            controller:
                                                                _loginPasswordController,
                                                            focusNode:
                                                                _loginPasswordFocusNode,
                                                            label: 'Password',
                                                            obscureText: true,
                                                            textInputAction:
                                                                TextInputAction
                                                                    .done,
                                                            onSubmitted: (_) {
                                                              _unfocusCurrentField();
                                                              _submit(vm);
                                                            },
                                                          ),
                                                        ],
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
                                                            value:
                                                                _registerRole,
                                                            items:
                                                                registerRoleOptions,
                                                            onChanged: (value) {
                                                              setState(() {
                                                                _registerRole =
                                                                    value;
                                                                if (value !=
                                                                    'driver') {
                                                                  _registerVehicleTypeId =
                                                                      null;
                                                                }
                                                              });
                                                            },
                                                          ),
                                                          if (_registerRole ==
                                                                  'driver' &&
                                                              !_isLoadingVehicleTypes) ...[
                                                            const SizedBox(
                                                              height:
                                                                  _authFieldSpacing,
                                                            ),
                                                            _AuthDropdownField(
                                                              label:
                                                                  'Vehicle Type',
                                                              value:
                                                                  _registerVehicleTypeId,
                                                              items: _vehicleTypes
                                                                  .map(
                                                                    (item) =>
                                                                        item.id ??
                                                                        '',
                                                                  )
                                                                  .where(
                                                                    (
                                                                      value,
                                                                    ) => value
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
                                                                if (match
                                                                    .isEmpty) {
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
                                                                if (name
                                                                    .isEmpty) {
                                                                  return slug;
                                                                }
                                                                if (slug
                                                                    .isEmpty) {
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
                                                            height:
                                                                _authFieldSpacing,
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
                                                                TextInputAction
                                                                    .next,
                                                            onSubmitted: (_) =>
                                                                _focusNext(
                                                                  _registerNameFocusNode,
                                                                ),
                                                          ),
                                                          const SizedBox(
                                                            height:
                                                                _authFieldSpacing,
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
                                                                TextInputAction
                                                                    .next,
                                                            onSubmitted: (_) =>
                                                                _focusNext(
                                                                  _registerPhoneFocusNode,
                                                                ),
                                                          ),
                                                          const SizedBox(
                                                            height:
                                                                _authFieldSpacing,
                                                          ),
                                                          _AuthTextField(
                                                            controller:
                                                                _registerPhoneController,
                                                            focusNode:
                                                                _registerPhoneFocusNode,
                                                            label: 'Phone',
                                                            keyboardType:
                                                                TextInputType
                                                                    .phone,
                                                            inputFormatters: const [
                                                              PhilippinesPhoneInputFormatter(),
                                                            ],
                                                            textInputAction:
                                                                TextInputAction
                                                                    .next,
                                                            onSubmitted: (_) =>
                                                                _focusNext(
                                                                  _registerPasswordFocusNode,
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
                                                          ],
                                                          const SizedBox(
                                                            height:
                                                                _authFieldSpacing,
                                                          ),
                                                          _AuthTextField(
                                                            controller:
                                                                _registerPasswordController,
                                                            focusNode:
                                                                _registerPasswordFocusNode,
                                                            label: 'Password',
                                                            obscureText: true,
                                                            textInputAction:
                                                                TextInputAction
                                                                    .done,
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
                                                            AppColors
                                                                .primaryColor,
                                                        side: const BorderSide(
                                                          color: AppColors
                                                              .primaryBorder,
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
                                                          fontWeight:
                                                              FontWeight.w700,
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
                                                            AppColors
                                                                .primaryColor,
                                                        foregroundColor:
                                                            Colors.white,
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
                                                                    strokeWidth:
                                                                        2.4,
                                                                    color: Colors
                                                                        .white,
                                                                  ),
                                                            )
                                                          : Text(
                                                              _isLoginMode
                                                                  ? 'Sign In'
                                                                  : 'Sign Up',
                                                              style: const TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
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
                                      child: ColoredBox(
                                        color: AppColors.primaryColor,
                                        child: Padding(
                                          padding: const EdgeInsets.all(24),
                                          child: Center(
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const SizedBox(
                                                  width: 28,
                                                  height: 28,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 3,
                                                    valueColor:
                                                        AlwaysStoppedAnimation<
                                                          Color
                                                        >(Colors.white),
                                                  ),
                                                ),
                                                const SizedBox(height: 16),
                                                Text(
                                                  _authFlowLoadingMessage,
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 15,
                                                    height: 1.25,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
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
          await _clearDraft();
          if (mounted) {
            setState(() {
              _resetLoginFields();
              _resetRegisterFields();
            });
          }
          await widget.onAuthenticated(user);
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
        _logRegisterPhoto(
          'account created user=${user.id ?? "-"} role=${user.role ?? "-"} '
          'hasPhoto=${user.photo?.trim().isNotEmpty == true}',
        );
        final uploadResult = await _completeRegisterImageUploads(user);
        final uploadedUser = uploadResult.user;
        _logRegisterPhoto(
          'upload flow finished user=${uploadedUser.id ?? "-"} '
          'hasPhoto=${uploadedUser.photo?.trim().isNotEmpty == true} '
          'error=${uploadResult.errorMessage ?? "-"}',
        );
        final registeredIdentifier = _registerEmailController.text.trim();
        final registeredPassword = _registerPasswordController.text;
        if (!mounted) {
          return;
        }
        if (uploadResult.errorMessage?.trim().isNotEmpty == true) {
          final rollbackMessage = await _rollbackFailedRegisteredUser(
            uploadedUser.id,
          );
          if (!mounted) {
            return;
          }
          final baseMessage = uploadResult.errorMessage!.trim();
          AppSnackbar.showError(
            context,
            rollbackMessage == null
                ? baseMessage
                : '$baseMessage $rollbackMessage',
          );
          return;
        }
        await _clearDraft();
        if (mounted) {
          setState(() {
            _resetLoginFields();
            _resetRegisterFields();
          });
        }
        if (uploadedUser.isActive ?? false) {
          await _showAuthFlowStage('Signing you in ...');
          final authenticatedUser = await vm.login(
            identifier: registeredIdentifier,
            password: registeredPassword,
          );
          if (!mounted) {
            return;
          }
          if (authenticatedUser != null) {
            _logRegisterPhoto(
              'automatic login resolved user=${authenticatedUser.id ?? "-"} '
              'hasPhoto=${authenticatedUser.photo?.trim().isNotEmpty == true}',
            );
            await widget.onAuthenticated(authenticatedUser);
          } else {
            _logRegisterPhoto(
              'automatic login fallback user=${uploadedUser.id ?? "-"} '
              'hasPhoto=${uploadedUser.photo?.trim().isNotEmpty == true}',
            );
            await widget.onAuthenticated(uploadedUser);
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
    } on AuthFailure catch (error) {
      if (mounted && error.message.trim().isNotEmpty) {
        AppSnackbar.showError(context, error.message.trim());
      }
    } catch (error) {
      if (mounted) {
        AppSnackbar.showError(context, error.toString());
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
    final upload = await _pickAuthImageUploadWithSourceChooser();
    if (upload == null || !mounted) {
      return;
    }
    setState(() {
      _registerProfilePhotoUpload = _PendingAuthImageUpload(
        bytes: Uint8List.fromList(upload.bytes),
        fileName: upload.fileName,
        size: upload.size,
        mimeType: upload.mimeType,
      );
    });
    _logRegisterPhoto(
      'photo selected file=${upload.fileName} bytes=${upload.bytes.length} '
      'mime=${upload.mimeType ?? "-"}',
    );
    await _persistDraftImmediately();
  }

  Future<void> _pickRegisterLicensePhoto() async {
    final upload = await _pickAuthImageUploadWithSourceChooser();
    if (upload == null || !mounted) {
      return;
    }
    setState(() {
      _registerLicensePhotoUpload = _PendingAuthImageUpload(
        bytes: Uint8List.fromList(upload.bytes),
        fileName: upload.fileName,
        size: upload.size,
        mimeType: upload.mimeType,
      );
      _registerLicenseController.text = upload.fileName;
    });
    await _persistDraftImmediately();
  }

  Future<_PendingAuthImageUpload?>
  _pickAuthImageUploadWithSourceChooser() async {
    final source = await _showAuthImageSourcePicker();
    if (source == null) {
      return null;
    }
    final pickedImage = source == AuthImagePickSource.camera
        ? await _captureAuthCameraImage()
        : await pickAuthImage(source);
    if (pickedImage == null) {
      return null;
    }
    return _PendingAuthImageUpload(
      bytes: pickedImage.bytes,
      fileName: pickedImage.fileName,
      size: pickedImage.size,
      mimeType: pickedImage.mimeType,
    );
  }

  Future<AuthPickedImage?> _captureAuthCameraImage() async {
    if (!authCameraSupported) {
      if (mounted) {
        AppSnackbar.showError(
          context,
          'Camera is not supported on this browser. Please use Gallery instead.',
        );
      }
      return null;
    }
    final session = createAuthCameraSession();
    _activeCameraSession = session;
    final initializeFuture = session.initialize();
    try {
      final image = await showAppDialog<AuthPickedImage>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) {
          var isCapturing = false;
          return StatefulBuilder(
            builder: (context, setModalState) {
              return Dialog(
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 24,
                ),
                elevation: 0,
                backgroundColor: Colors.transparent,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final modalWidth = constraints.maxWidth.clamp(0.0, 760.0);
                    final isCompact = modalWidth < 560;
                    return Align(
                      alignment: Alignment.center,
                      child: Container(
                        width: modalWidth,
                        padding: EdgeInsets.fromLTRB(
                          isCompact ? 16 : 20,
                          isCompact ? 16 : 20,
                          isCompact ? 16 : 20,
                          isCompact ? 16 : 20,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: AppColors.primaryBorder),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x261A1333),
                              blurRadius: 28,
                              offset: Offset(0, 14),
                            ),
                          ],
                        ),
                        child: FutureBuilder<void>(
                          future: initializeFuture,
                          builder: (context, snapshot) {
                            final hasError = snapshot.hasError;
                            final isReady =
                                snapshot.connectionState ==
                                    ConnectionState.done &&
                                !hasError;
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 42,
                                      height: 42,
                                      decoration: BoxDecoration(
                                        color: AppColors.primarySurface,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: AppColors.primaryBorder,
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.photo_camera_outlined,
                                        color: AppColors.primaryColor,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Take Photo',
                                            style: TextStyle(
                                              color: AppColors.textPrimary,
                                              fontSize: 20,
                                              fontWeight: FontWeight.w800,
                                              height: 1.1,
                                            ),
                                          ),
                                          if (hasError) ...[
                                            const SizedBox(height: 4),
                                            const Text(
                                              'Camera permission was denied or unavailable.',
                                              style: TextStyle(
                                                color: AppColors.textSecondary,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500,
                                                height: 1.3,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    MouseRegion(
                                      cursor: SystemMouseCursors.click,
                                      child: Container(
                                        width: 42,
                                        height: 42,
                                        decoration: BoxDecoration(
                                          color: AppColors.primarySurface,
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          border: Border.all(
                                            color: AppColors.primaryBorder,
                                          ),
                                        ),
                                        child: IconButton(
                                          tooltip: 'Switch camera',
                                          iconSize: 20,
                                          onPressed: isReady && !isCapturing
                                              ? () async {
                                                  setModalState(
                                                    () => isCapturing = true,
                                                  );
                                                  try {
                                                    await session
                                                        .switchCamera();
                                                  } finally {
                                                    if (context.mounted) {
                                                      setModalState(
                                                        () =>
                                                            isCapturing = false,
                                                      );
                                                    }
                                                  }
                                                }
                                              : null,
                                          icon: const Icon(
                                            Icons.cameraswitch_outlined,
                                          ),
                                          color: AppColors.primaryColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 18),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(24),
                                  child: Container(
                                    width: double.infinity,
                                    constraints: BoxConstraints(
                                      maxHeight: isCompact ? 420 : 520,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.primaryDark,
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                    child: AspectRatio(
                                      aspectRatio: isCompact ? 3 / 4 : 4 / 3,
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          if (hasError)
                                            const Center(
                                              child: Padding(
                                                padding: EdgeInsets.all(24),
                                                child: Text(
                                                  'We could not open the camera. Check browser permission settings and try again.',
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                    height: 1.4,
                                                  ),
                                                ),
                                              ),
                                            )
                                          else if (!isReady)
                                            const Center(
                                              child: CircularProgressIndicator(
                                                color: Colors.white,
                                              ),
                                            )
                                          else
                                            HtmlElementView(
                                              viewType: session.viewType!,
                                            ),
                                          IgnorePointer(
                                            child: Padding(
                                              padding: EdgeInsets.all(
                                                isCompact ? 18 : 24,
                                              ),
                                              child: DecoratedBox(
                                                decoration: BoxDecoration(
                                                  borderRadius:
                                                      BorderRadius.circular(24),
                                                  border: Border.all(
                                                    color: const Color(
                                                      0xCCFFFFFF,
                                                    ),
                                                    width: 2,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Flex(
                                  direction: isCompact
                                      ? Axis.vertical
                                      : Axis.horizontal,
                                  children: [
                                    if (!isCompact)
                                      Expanded(
                                        child: OutlinedButton(
                                          onPressed: () =>
                                              Navigator.of(dialogContext).pop(),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor:
                                                AppColors.textPrimary,
                                            side: const BorderSide(
                                              color: AppColors.primaryBorder,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 15,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                            ),
                                          ),
                                          child: const Text('Cancel'),
                                        ),
                                      )
                                    else
                                      SizedBox(
                                        width: double.infinity,
                                        child: FilledButton(
                                          onPressed: !isReady || isCapturing
                                              ? null
                                              : () async {
                                                  setModalState(() {
                                                    isCapturing = true;
                                                  });
                                                  try {
                                                    final image = await session
                                                        .capture();
                                                    if (dialogContext.mounted) {
                                                      Navigator.of(
                                                        dialogContext,
                                                      ).pop(image);
                                                    }
                                                  } catch (error) {
                                                    if (mounted) {
                                                      AppSnackbar.showError(
                                                        this.context,
                                                        userFacingErrorMessage(
                                                          error,
                                                          fallback:
                                                              'We could not capture the image right now.',
                                                        ),
                                                      );
                                                    }
                                                    if (dialogContext.mounted) {
                                                      setModalState(() {
                                                        isCapturing = false;
                                                      });
                                                    }
                                                  }
                                                },
                                          style: FilledButton.styleFrom(
                                            backgroundColor:
                                                AppColors.primaryColor,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 16,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                            ),
                                          ),
                                          child: Text(
                                            isCapturing
                                                ? 'Capturing ...'
                                                : 'Capture Photo',
                                          ),
                                        ),
                                      ),
                                    if (!isCompact) ...[
                                      const SizedBox(width: 12),
                                      Expanded(
                                        flex: 2,
                                        child: FilledButton(
                                          onPressed: !isReady || isCapturing
                                              ? null
                                              : () async {
                                                  setModalState(() {
                                                    isCapturing = true;
                                                  });
                                                  try {
                                                    final image = await session
                                                        .capture();
                                                    if (dialogContext.mounted) {
                                                      Navigator.of(
                                                        dialogContext,
                                                      ).pop(image);
                                                    }
                                                  } catch (error) {
                                                    if (mounted) {
                                                      AppSnackbar.showError(
                                                        this.context,
                                                        userFacingErrorMessage(
                                                          error,
                                                          fallback:
                                                              'We could not capture the image right now.',
                                                        ),
                                                      );
                                                    }
                                                    if (dialogContext.mounted) {
                                                      setModalState(() {
                                                        isCapturing = false;
                                                      });
                                                    }
                                                  }
                                                },
                                          style: FilledButton.styleFrom(
                                            backgroundColor:
                                                AppColors.primaryColor,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 15,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                            ),
                                          ),
                                          child: Text(
                                            isCapturing
                                                ? 'Capturing ...'
                                                : 'Capture Photo',
                                          ),
                                        ),
                                      ),
                                    ],
                                    if (isCompact) ...[
                                      const SizedBox(height: 10),
                                      SizedBox(
                                        width: double.infinity,
                                        child: OutlinedButton(
                                          onPressed: () =>
                                              Navigator.of(dialogContext).pop(),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor:
                                                AppColors.textPrimary,
                                            side: const BorderSide(
                                              color: AppColors.primaryBorder,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 14,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                            ),
                                          ),
                                          child: const Text('Cancel'),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      );
      return image;
    } finally {
      if (identical(_activeCameraSession, session)) {
        _activeCameraSession = null;
      }
      await SchedulerBinding.instance.endOfFrame;
      await session.dispose();
    }
  }

  Future<AuthImagePickSource?> _showAuthImageSourcePicker() {
    return showAppModalBottomSheet<AuthImagePickSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.primaryBorder),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Choose Photo Source',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _AuthImageSourceAction(
                      icon: Icons.photo_camera_outlined,
                      label: 'Camera',
                      onTap: () => Navigator.of(
                        sheetContext,
                      ).pop(AuthImagePickSource.camera),
                    ),
                    const SizedBox(height: 10),
                    _AuthImageSourceAction(
                      icon: Icons.photo_library_outlined,
                      label: 'Gallery',
                      onTap: () => Navigator.of(
                        sheetContext,
                      ).pop(AuthImagePickSource.gallery),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
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
        _logRegisterPhoto(
          'storage upload start user=${updatedUser.id} '
          'file=${profileUpload.fileName} bytes=${profileUpload.bytes.length}',
        );
        updatedUser = await _authRequest.saveUserPhoto(
          userId: updatedUser.id!,
          bytes: profileUpload.bytes,
          fileName: profileUpload.fileName,
          mimeType: profileUpload.mimeType,
          size: profileUpload.size,
        );
        _logRegisterPhoto(
          'storage upload saved user=${updatedUser.id ?? "-"} '
          'hasPhoto=${updatedUser.photo?.trim().isNotEmpty == true}',
        );
      }

      final licenseUpload = _registerLicensePhotoUpload;
      if (licenseUpload != null &&
          normalizeRoleKey(updatedUser.role) == 'driver' &&
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
      errorMessage = exactUserErrorMessage(error);
    }

    return _RegisterUploadResult(user: updatedUser, errorMessage: errorMessage);
  }

  void _logRegisterPhoto(String message) {
    debugPrint(
      '[${DateTime.now().toIso8601String()}][RegisterProfilePhoto] $message',
    );
  }

  Future<String?> _rollbackFailedRegisteredUser(String? userId) async {
    final normalizedUserId = normalizeId(userId);
    if (normalizedUserId == null) {
      return 'The account was not completed because the required image failed.';
    }
    try {
      await _authRequest.deleteUser(normalizedUserId);
      return null;
    } catch (_) {
      return 'The account image failed, and cleanup may still be pending.';
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

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'bytes': bytes,
      'file_name': fileName,
      'size': size,
      'mime_type': mimeType,
    };
  }
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
    const activeFillColor = Colors.white;
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
                    : Colors.white,
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
    const hoveredFillColor = Colors.white;
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
          fillColor: _isPressed || _isHovered ? hoveredFillColor : Colors.white,
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
                  Image.memory(
                    previewBytes!,
                    key: ValueKey<int>(previewBytes!.length),
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.medium,
                  ),
                if (!hasPreview)
                  const Center(
                    child: Icon(
                      Icons.photo_camera_rounded,
                      color: AppColors.primaryColor,
                      size: 22,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthImageSourceAction extends StatelessWidget {
  const _AuthImageSourceAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppMousePressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F1FF),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.primaryBorder),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primaryColor, size: 20),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
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
      decoration: adminPlainDropdownDecoration(label, radius: 18).copyWith(
        constraints: const BoxConstraints(minHeight: adminModalFieldMinHeight),
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
