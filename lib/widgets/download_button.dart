import 'package:flutter/material.dart';

class DownloadButton extends StatefulWidget {
  /// 0.0 to 1.0 for an active download, -1 for idle, -2 for waiting.
  final double progress;

  /// The last attempt failed; tapping retries instead of restarting silently.
  final bool failed;

  final VoidCallback onPressed;

  const DownloadButton({
    super.key,
    required this.progress,
    required this.onPressed,
    this.failed = false,
  });

  @override
  State<DownloadButton> createState() => _DownloadButtonState();
}

class _DownloadButtonState extends State<DownloadButton> {
  @override
  Widget build(BuildContext context) {
    final isRu = Localizations.localeOf(context).languageCode == 'ru';
    final isIdle = widget.progress == -1;
    final isWaiting = widget.progress == -2;
    final isComplete = widget.progress >= 1.0 && !widget.failed;
    final isDownloading = !widget.failed && !isIdle && !isWaiting && !isComplete;

    // Palette: ["#353535", "#ffffff", "#d2d7df", "#bdbbb0", "#8a897c"]
    Color bgColor;
    Color fgColor;
    Border? border;
    Color barColor;

    if (widget.failed) {
      bgColor = const Color(0xFF352424);
      fgColor = const Color(0xFFF2B8B5);
      border = Border.all(color: const Color(0xFFB3261E), width: 1);
      barColor = const Color(0xFFB3261E);
    } else if (isComplete) {
      bgColor = const Color(0xFF8A897C);
      fgColor = Colors.white;
      border = null;
      barColor = const Color(0xFF8A897C);
    } else if (isIdle) {
      bgColor = const Color(0xFF353535);
      fgColor = const Color(0xFFD2D7DF);
      border = Border.all(color: const Color(0xFF8A897C).withValues(alpha: 0.5), width: 1);
      barColor = const Color(0xFF8A897C);
    } else {
      bgColor = const Color(0xFF282828);
      fgColor = Colors.white;
      border = Border.all(color: const Color(0xFFBDBBB0), width: 1);
      barColor = const Color(0xFF8A897C);
    }

    final label = widget.failed
        ? (isRu ? 'Повтор' : 'Retry')
        : isComplete
            ? 'CBZ'
            : isWaiting
                ? (isRu ? 'Ожидание' : 'Wait...')
                : isIdle
                    ? (isRu ? 'Скачать' : 'Load')
                    : '${(widget.progress * 100).toInt()}%';

    final icon = widget.failed
        ? Icons.sync_problem_rounded
        : isComplete
            ? Icons.check_circle_outline_rounded
            : isWaiting
                ? Icons.hourglass_empty_rounded
                : Icons.file_download_outlined;

    return InkWell(
      onTap: widget.onPressed,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        height: 38,
        width: 105,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
          border: border,
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              alignment: Alignment.center,
              children: [
                if (isDownloading)
                  Positioned(
                    left: 0, top: 0, bottom: 0,
                    child: Container(
                      width: constraints.maxWidth * widget.progress.clamp(0.0, 1.0),
                      color: barColor.withValues(alpha: 0.6),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: 18, color: fgColor),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: fgColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}