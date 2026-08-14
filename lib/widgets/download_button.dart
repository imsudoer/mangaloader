import 'package:flutter/material.dart';

class DownloadButton extends StatefulWidget {
  final double progress; // 0.0 to 1.0, -1 for idle, -2 for waiting
  final VoidCallback onPressed;

  const DownloadButton({super.key, required this.progress, required this.onPressed});

  @override
  State<DownloadButton> createState() => _DownloadButtonState();
}

class _DownloadButtonState extends State<DownloadButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isIdle = widget.progress == -1;
    final isWaiting = widget.progress == -2;
    final isComplete = widget.progress >= 1.0;
    final isDownloading = !isIdle && !isWaiting && !isComplete;

    // Palette: ["#353535", "#ffffff", "#d2d7df", "#bdbbb0", "#8a897c"]
    Color bgColor;
    Color fgColor;
    Border? border;

    if (isComplete) {
      bgColor = const Color(0xFF8A897C);
      fgColor = Colors.white;
      border = null;
    } else if (isIdle) {
      bgColor = const Color(0xFF353535);
      fgColor = const Color(0xFFD2D7DF);
      border = Border.all(color: const Color(0xFF8A897C).withValues(alpha: 0.5), width: 1);
    } else {
      bgColor = const Color(0xFF282828);
      fgColor = Colors.white;
      border = Border.all(color: const Color(0xFFBDBBB0), width: 1);
    }

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
                      color: const Color(0xFF8A897C).withValues(alpha: 0.6),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isComplete 
                          ? Icons.check_circle_outline_rounded 
                          : isWaiting 
                            ? Icons.hourglass_empty_rounded 
                            : Icons.file_download_outlined,
                        size: 18,
                        color: fgColor,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          isComplete 
                            ? 'CBZ' 
                            : isWaiting 
                              ? 'Wait...' 
                              : isIdle 
                                ? 'Load' 
                                : '${(widget.progress * 100).toInt()}%',
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
