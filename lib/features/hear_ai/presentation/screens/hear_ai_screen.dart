import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:komunika/app/themes/app_colors.dart';
import 'package:komunika/core/extensions/snackbar_extension.dart';
import 'package:komunika/core/services/custom_bluetooth_service.dart';
import 'package:komunika/features/hear_ai/domain/entities/hear_ai_result.dart';
import 'package:komunika/features/hear_ai/presentation/cubit/hear_ai_cubit.dart';
import 'package:komunika/features/hear_ai/presentation/widgets/hear_ai_error_ui.dart';
import 'package:komunika/features/hear_ai/presentation/widgets/hear_ai_idle_ui.dart';
import 'package:komunika/features/hear_ai/presentation/widgets/hear_ai_processing_ui.dart';
import 'package:komunika/features/hear_ai/presentation/widgets/hear_ai_recording_ui.dart';
import 'package:komunika/features/hear_ai/presentation/widgets/hear_ai_success_ui.dart';
import 'package:permission_handler/permission_handler.dart';

// TODO fix the bug where toggling from normal to continuous mode makes the app stuck in processing
class HearAiScreen extends StatefulWidget {
  const HearAiScreen({super.key});

  @override
  State<HearAiScreen> createState() => _HearAiScreenState();
}

class _HearAiScreenState extends State<HearAiScreen> {
  bool _isContinuousModeEnabled = false;

  // ? function figures out the main action button's text and callback
  // TODO : remove button widget entirely in this method as its not even used  / displayed
  Map<String, dynamic> _getActionButtonConfig(
    BuildContext context,
    HearAiState state,
  ) {
    String buttonText;
    VoidCallback? onPressed;
    Color buttonColor = AppColors.haiti;
    bool showButton = true;

    // ? handle permission-related states
    if (state is HearAiPermissionNeeded) {
      buttonText =
          state.isPermanentlyDenied ? "Open Settings" : "Grant Permission";
      onPressed =
          state.isPermanentlyDenied
              ? () => openAppSettings()
              : () => context.read<HearAiCubit>().requestMicrophonePermission();
      buttonColor = Colors.orangeAccent;
      showButton = false;
    } else if (state is HearAiProcessing) {
      buttonText = "Processing...";
      onPressed = null;
      showButton = false; //
    } else {
      //? handle recording and ready states
      if (_isContinuousModeEnabled) {
        if (state is HearAiRecording) {
          buttonText = "Stop Continuous Listening";
          onPressed =
              () => context.read<HearAiCubit>().stopContinuousListening();
          buttonColor = Colors.orangeAccent;
          showButton = false;
        } else {
          buttonText = "Start Continuous Listening";
          onPressed =
              () => context.read<HearAiCubit>().startContinuousListening();
          buttonColor = AppColors.deluge;
          showButton = false;
        }
      } else {
        if (state is HearAiRecording) {
          buttonText = "Stop Manual Recording";
          onPressed =
              () => context.read<HearAiCubit>().stopAndProcessRecording();
          buttonColor = Colors.redAccent;
          showButton = false;
        } else {
          buttonText = "Start Manual Recording";
          onPressed = () => context.read<HearAiCubit>().startRecording();
          showButton = false;
        }
      }
    }

    return {
      "text": buttonText,
      "action": onPressed,
      "color": buttonColor,
      "show": showButton,
    };
  }

  String responseFromBluetooth = "";

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<HearAiCubit, HearAiState>(
      listener: (context, state) async {
        if (state is HearAiError) {
          if (state is! HearAiPermissionNeeded) {
            context.customShowErrorSnackBar(state.message);
          }
        }
        if (state is HearAiSuccess) {
          // print(
          //   "AI Success in UI: ${state.latestResult.eventType} - ${state.latestResult.transcription}",
          // );
          final CustomBluetoothService bleService =
              context.read<CustomBluetoothService>();
          if (bleService.isConnected.value) {
            List<int> command = [0x02, 0x01]; // ? default command data

            final List<String> normalSpeechCategories = [
              "SPEECH_NEUTRAL",
              "SPEECH_QUESTION",
              "SPEECH_HAPPY_EXCITED",
              "SPEECH_ROMANTIC",
              "SPEECH_SAD",
              "SPEECH_UNCLEAR",
            ];

            final List<String> urgentSpeechCategories = [
              "SPEECH_ANGRY_STRESSED",
              "SPEECH_URGENT_IMPORTANT",
              "SPEECH_INSTRUCTION",
            ];

            final List<String> normalSoundCategories = [
              "SOUND_DOORBELL_KNOCK",
              "SOUND_PHONE_RINGING",
              "SOUND_PERSON_COUGH_SNEEZE",
              "SOUND_ANIMAL_SOUND",
              "SOUND_MUSIC",
              "SOUND_CROWD_NOISE",
              "AMBIENT_NOISE",
            ];

            final List<String> emergencySoundCategories = [
              "SOUND_ALARM",
              "SOUND_VEHICLE_HORN",
              "SOUND_LOUD_IMPACT",
              "SOUND_EXPLOSION",
              "SOUND_PERSON_SCREAMING",
              "SOUND_BABY_CRYING",
              "SOUND_GENERAL_LOUD",
            ];
            final String eventType = state.latestResult.eventType;

            // ? customize command based on eventType

            if (normalSpeechCategories.contains(eventType)) {
              command = [0x02, 0x01]; //? normal speech
            } else if (urgentSpeechCategories.contains(eventType)) {
              command = [0x02, 0x04]; //? urgent speech
            } else if (normalSoundCategories.contains(eventType)) {
              command = [0x02, 0x02]; //? normal sound
            } else if (emergencySoundCategories.contains(eventType)) {
              command = [0x02, 0x04]; //? emergency Sound
            } else {
              // print(
              //   "Unknown eventType: $eventType, sending default/neutral command.",
              // );
              command = [
                0x02,
                0x01,
              ]; //? neutral or default command different from others (should be at least lol)
            }
            responseFromBluetooth = await bleService.sendCommandBytes(command);
          } else {
            // print("ImHEAR Band not connected, can't send vibration.");
            responseFromBluetooth = "Can't connect to device";
          }
        }
      },
      builder: (context, state) {
        final List<HearAiResult> history =
            context.watch<HearAiCubit>().resultsHistory;

        Widget topContent;
        final cfg = _getActionButtonConfig(context, state);

        if (state is HearAiInitial || state is HearAiReadyToRecord) {
          topContent = HearAiIdleUi(
            onTap:
                _isContinuousModeEnabled
                    ? () =>
                        context.read<HearAiCubit>().startContinuousListening()
                    : () => context.read<HearAiCubit>().startRecording(),
            permissionNeeded: false,
          );
        } else if (state is HearAiPermissionNeeded) {
          topContent = HearAiIdleUi(
            onTap: cfg["action"],
            permissionNeeded: true,
            buttonText: cfg["text"],
          );
        } else if (state is HearAiRecording) {
          topContent = HearAiRecordingUi(
            onTap:
                _isContinuousModeEnabled
                    ? () =>
                        context
                            .read<HearAiCubit>()
                            .stopContinuousListening() // ? In continuous, stop fully
                    : () =>
                        context
                            .read<HearAiCubit>()
                            .stopAndProcessRecording(), // ? In manual, stop & process
          );
        } else if (state is HearAiProcessing) {
          topContent = const HearAiProcessingUi();
        } else if (state is HearAiSuccess) {
          topContent = HearAiSuccessUi(
            // resultsHistory: state.resultsHistory,
            // latestResult: state.latestResult,
            onStartNextRecording:
                () => context.read<HearAiCubit>().startRecording(),
            isContinuousMode: _isContinuousModeEnabled,
          );
        } else if (state is HearAiError) {
          topContent = HearAiErrorUi(
            message: state.message,
            onTap: cfg["action"], //? will be "Retry Permission/Init"
          );
        } else {
          topContent = const Text("Unknown State");
        }

        return Padding(
          padding: const EdgeInsets.only(
            top: 24.0,
            bottom: 8.0,
            left: 24.0,
            right: 24.0,
          ),
          child: Column(
            children: <Widget>[
              // ? Toggle  Switch (Continuous or not)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Text(
                    "Continuous Mode",
                    style: TextStyle(color: AppColors.haiti),
                  ),
                  Switch(
                    value: _isContinuousModeEnabled,
                    onChanged: (bool value) {
                      setState(() {
                        _isContinuousModeEnabled = value;
                      });
                    },
                    activeColor: AppColors.bittersweet,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              topContent,
              if (cfg["show"] &&
                  state
                      is! HearAiPermissionNeeded) // ? hide button if permission is needed
                Padding(
                  padding: const EdgeInsets.only(top: 20.0),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cfg["color"],
                        padding: const EdgeInsets.symmetric(
                          horizontal: 40,
                          vertical: 15,
                        ),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          color: AppColors.white,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: cfg["action"],
                      child: Text(
                        cfg["text"],
                        style: const TextStyle(color: AppColors.white),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 20),

              // ? persistent history list
              Card(
                color: const Color.fromARGB(255, 180, 231, 255),
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide.none,
                ),
                margin: const EdgeInsets.only(bottom: 6),
                child: const ListTile(
                  leading: Icon(
                    Icons.track_changes_outlined,
                    color: AppColors.haiti,
                  ),

                  title: Text(
                    'Listening Results',
                    style: TextStyle(
                      color: AppColors.haiti,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  // ? for testing bluetooth response
                  // subtitle: Text(
                  //   'Device response: $responseFromBluetooth',
                  //   style: const TextStyle(
                  //     color: AppColors.bittersweet,
                  //     fontWeight: FontWeight.w600,
                  //   ),
                  // ),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                ),
              ),
              const Divider(color: AppColors.haiti),

              Expanded(
                child:
                    history.isEmpty
                        ? const Center(
                          child: Text(
                            "No results yet.",
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                        : ListView.builder(
                          itemCount: history.length,
                          itemBuilder: (ctx, i) {
                            final r = history[i];
                            return Card(
                              color: AppColors.haiti,
                              elevation: 2,
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            r.eventType,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 18,
                                              color: AppColors.bittersweet,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          DateFormat(
                                            "HH:mm:ss",
                                          ).format(r.timestamp),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.lavender.withAlpha(
                                              180,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),

                                    const SizedBox(height: 8),
                                    if (r.transcription != "N/A" &&
                                        r.transcription.isNotEmpty)
                                      Text(
                                        "Transcription: ${r.transcription}",
                                        style: const TextStyle(
                                          color: AppColors.lavender,
                                        ),
                                      ),
                                    if (r.details.isNotEmpty &&
                                        r.details != "N/A")
                                      Text(
                                        "Details: ${r.details}",
                                        style: const TextStyle(
                                          color: AppColors.columbiaBlue,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
              ),
            ],
          ),
        );
      },
    );
  }
}
