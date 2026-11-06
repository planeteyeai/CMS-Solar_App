import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/avatar_service.dart';
import '../theme/app_theme.dart';
import 'ui_kit.dart';
import 'user_avatar.dart';

/// Bottom sheet: take a selfie / choose a photo / remove, then store it in the database.
Future<void> changeProfilePhoto(BuildContext context, int userId, String name) async {
  final auth = context.read<AuthService>();
  final messenger = ScaffoldMessenger.of(context);
  final hasPhoto = AvatarService.cached(userId) != null;

  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    backgroundColor: AppTheme.surfaceCard,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          UserAvatar(userId: userId, name: name, size: 84),
          const SizedBox(height: 12),
          Text('Profile photo',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text('Your team lead, project manager and superadmin will see this photo.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          const SizedBox(height: 16),
          ListTile(
            leading: Icon(Icons.photo_camera_rounded, color: AppTheme.accent),
            title: const Text('Take a photo'),
            onTap: () => Navigator.pop(context, 'camera'),
          ),
          ListTile(
            leading: Icon(Icons.photo_library_rounded, color: AppTheme.accent),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(context, 'gallery'),
          ),
          if (hasPhoto)
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: AppTheme.accentRed),
              title: const Text('Remove photo'),
              onTap: () => Navigator.pop(context, 'remove'),
            ),
        ]),
      ),
    ),
  );
  if (choice == null) return;

  if (choice == 'remove') {
    final err = await AvatarService.remove(auth, userId);
    messenger.showSnackBar(SnackBar(content: Text(err ?? 'Profile photo removed')));
    return;
  }

  try {
    final file = await ImagePicker().pickImage(
      source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
      preferredCameraDevice: CameraDevice.front,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (bytes.length > 300 * 1024) {
      messenger.showSnackBar(const SnackBar(
          content: Text('That photo is too large. Please choose a smaller one.')));
      return;
    }
    messenger.showSnackBar(const SnackBar(content: Text('Saving photo…')));
    final err = await AvatarService.upload(auth, userId, bytes);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(err ?? 'Profile photo saved')));
  } catch (_) {
    messenger.showSnackBar(const SnackBar(
        content: Text('Could not open the camera or gallery. Check app permissions.')));
  }
}

/// Card shown on the home screen until the user has a profile photo.
class PhotoPrompt extends StatelessWidget {
  final int userId;
  final String name;
  const PhotoPrompt({super.key, required this.userId, required this.name});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    return ValueListenableBuilder<int>(
      valueListenable: AvatarService.revision,
      builder: (_, __, ___) => FutureBuilder(
        future: AvatarService.load(auth, userId),
        initialData: AvatarService.cached(userId),
        builder: (_, snap) {
          // Only prompt once we know there is no photo.
          if (snap.data != null || !AvatarService.hasLoaded(userId)) {
            return const SizedBox.shrink();
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AppCard(
              onTap: () => changeProfilePhoto(context, userId, name),
              borderColor: AppTheme.accent.withOpacity(0.5),
              child: Row(children: [
                Icon(Icons.account_circle_rounded, color: AppTheme.accent, size: 34),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Add your profile photo',
                        style: TextStyle(
                            color: AppTheme.textPrimary, fontWeight: FontWeight.w800, fontSize: 15)),
                    SizedBox(height: 2),
                    Text('So your team lead and manager can recognise you on the site map.',
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 12.5, height: 1.35)),
                  ]),
                ),
                Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
              ]),
            ),
          );
        },
      ),
    );
  }
}
