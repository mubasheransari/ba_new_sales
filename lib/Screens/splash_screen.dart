
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Image.asset(
          'assets/ba_logo.png',
          width: 220,
          height: 220,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}




// import 'dart:math' as math;

// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:ords_ba/Theme/app_theme.dart';

// /// Animated splash: gradient backdrop with a soft dot grid and drifting
// /// glows, a pulsing logo, staggered title / tagline and a shimmer loader.
// /// Uses only built-in Flutter animation (no extra packages).
// class SplashScreen extends StatefulWidget {
//   const SplashScreen({super.key});

//   @override
//   State<SplashScreen> createState() => _SplashScreenState();
// }

// class _SplashScreenState extends State<SplashScreen>
//     with TickerProviderStateMixin {
//   // One-shot entrance and a repeating loop for the ambient motion.
//   late final AnimationController _intro = AnimationController(
//     vsync: this,
//     duration: const Duration(milliseconds: 1600),
//   )..forward();

//   late final AnimationController _loop = AnimationController(
//     vsync: this,
//     duration: const Duration(milliseconds: 3200),
//   )..repeat();

//   Animation<double> _stage(double a, double b, Curve c) =>
//       CurvedAnimation(parent: _intro, curve: Interval(a, b, curve: c));

//   late final Animation<double> _logoScale =
//       _stage(0.00, 0.50, Curves.easeOutBack);
//   late final Animation<double> _logoFade = _stage(0.00, 0.35, Curves.easeOut);
//   late final Animation<double> _titleAnim =
//       _stage(0.35, 0.70, Curves.easeOutCubic);
//   late final Animation<double> _tagAnim =
//       _stage(0.50, 0.85, Curves.easeOutCubic);
//   late final Animation<double> _footerAnim =
//       _stage(0.65, 1.00, Curves.easeOut);

//   @override
//   void dispose() {
//     _intro.dispose();
//     _loop.dispose();
//     super.dispose();
//   }

//   Widget _rise(Animation<double> a, Widget child) => FadeTransition(
//         opacity: a,
//         child: SlideTransition(
//           position: Tween<Offset>(
//             begin: const Offset(0, 0.35),
//             end: Offset.zero,
//           ).animate(a),
//           child: child,
//         ),
//       );

//   @override
//   Widget build(BuildContext context) {
//     return AnnotatedRegion<SystemUiOverlayStyle>(
//       value: SystemUiOverlayStyle.light,
//       child: Scaffold(
//         body: Container(
//           width: double.infinity,
//           height: double.infinity,
//           decoration: const BoxDecoration(
//             gradient: LinearGradient(
//               colors: [
//                 AppColors.redBright,
//                 AppColors.red,
//                 AppColors.redDeep,
//               ],
//               stops: [0.0, 0.5, 1.0],
//               begin: Alignment.topLeft,
//               end: Alignment.bottomRight,
//             ),
//           ),
//           child: Stack(
//             children: [
//               // Soft dot grid.
//               Positioned.fill(
//                 child: CustomPaint(painter: _DotGridPainter()),
//               ),

//               // Drifting glows.
//               AnimatedBuilder(
//                 animation: _loop,
//                 builder: (_, __) {
//                   final dx = math.sin(_loop.value * 2 * math.pi) * 16;
//                   final dy = math.cos(_loop.value * 2 * math.pi) * 16;
//                   return Stack(
//                     children: [
//                       Positioned(
//                         top: -110 + dy,
//                         right: -90 + dx,
//                         child: const _Glow(size: 320, alpha: 0.30),
//                       ),
//                       Positioned(
//                         bottom: -130 - dy,
//                         left: -100 - dx,
//                         child: const _Glow(size: 360, alpha: 0.22),
//                       ),
//                     ],
//                   );
//                 },
//               ),

//               // Centre content.
//               Center(
//                 child: Column(
//                   mainAxisSize: MainAxisSize.min,
//                   children: [
//                     _buildLogo(),
//                     const SizedBox(height: 30),
//                     _rise(
//                       _titleAnim,
//                       const Text(
//                         'BA Sales',
//                         style: TextStyle(
//                           color: Colors.white,
//                           fontSize: 36,
//                           fontWeight: FontWeight.w800,
//                           letterSpacing: 1.0,
//                           shadows: [
//                             Shadow(
//                               color: Color(0x33000000),
//                               blurRadius: 12,
//                               offset: Offset(0, 4),
//                             ),
//                           ],
//                         ),
//                       ),
//                     ),
//                     const SizedBox(height: 12),
//                     _rise(
//                       _tagAnim,
//                       Container(
//                         padding: const EdgeInsets.symmetric(
//                             horizontal: 16, vertical: 7),
//                         decoration: BoxDecoration(
//                           color: Colors.white.withValues(alpha: 0.16),
//                           borderRadius: BorderRadius.circular(30),
//                           border: Border.all(
//                             color: Colors.white.withValues(alpha: 0.28),
//                           ),
//                         ),
//                         child: Text(
//                           'Attendance & daily sales',
//                           style: TextStyle(
//                             color: Colors.white.withValues(alpha: 0.95),
//                             fontSize: 13.5,
//                             letterSpacing: 0.4,
//                           ),
//                         ),
//                       ),
//                     ),
//                   ],
//                 ),
//               ),

//               // Footer loader.
//               Positioned(
//                 left: 0,
//                 right: 0,
//                 bottom: 0,
//                 child: SafeArea(
//                   child: Padding(
//                     padding: const EdgeInsets.only(bottom: 36),
//                     child: FadeTransition(
//                       opacity: _footerAnim,
//                       child: Column(
//                         mainAxisSize: MainAxisSize.min,
//                         children: [
//                           _buildLoader(),
//                           const SizedBox(height: 14),
//                           Text(
//                             'Getting things ready...',
//                             style: TextStyle(
//                               color: Colors.white.withValues(alpha: 0.8),
//                               fontSize: 12.5,
//                               letterSpacing: 0.5,
//                             ),
//                           ),
//                         ],
//                       ),
//                     ),
//                   ),
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }

//   /// Logo card with two pulsing rings behind it.
//   Widget _buildLogo() {
//     return SizedBox(
//       width: 190,
//       height: 190,
//       child: Stack(
//         alignment: Alignment.center,
//         children: [
//           // Pulsing rings.
//           AnimatedBuilder(
//             animation: _loop,
//             builder: (_, __) {
//               Widget ring(double offset) {
//                 final t = (_loop.value + offset) % 1.0;
//                 return Opacity(
//                   opacity: ((1 - t) * 0.40).clamp(0.0, 1.0),
//                   child: Transform.scale(
//                     scale: 0.62 + t * 0.62,
//                     child: Container(
//                       width: 190,
//                       height: 190,
//                       decoration: BoxDecoration(
//                         shape: BoxShape.circle,
//                         border: Border.all(color: Colors.white, width: 1.6),
//                       ),
//                     ),
//                   ),
//                 );
//               }

//               return Stack(
//                 alignment: Alignment.center,
//                 children: [ring(0.0), ring(0.5)],
//               );
//             },
//           ),

//           // The logo card.
//           FadeTransition(
//             opacity: _logoFade,
//             child: ScaleTransition(
//               scale: _logoScale,
//               child: Container(
//                 width: 112,
//                 height: 112,
//                 decoration: BoxDecoration(
//                   gradient: const LinearGradient(
//                     colors: [Colors.white, AppColors.redTint],
//                     begin: Alignment.topLeft,
//                     end: Alignment.bottomRight,
//                   ),
//                   borderRadius: BorderRadius.circular(34),
//                   boxShadow: [
//                     BoxShadow(
//                       color: Colors.black.withValues(alpha: 0.22),
//                       blurRadius: 34,
//                       offset: const Offset(0, 16),
//                     ),
//                     BoxShadow(
//                       color: Colors.white.withValues(alpha: 0.35),
//                       blurRadius: 24,
//                       spreadRadius: 1,
//                     ),
//                   ],
//                 ),
//                 child: const Icon(
//                   Icons.storefront_rounded,
//                   size: 58,
//                   color: AppColors.red,
//                 ),
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   /// Slim bar with a light sweep that runs along it.
//   Widget _buildLoader() {
//     return ClipRRect(
//       borderRadius: BorderRadius.circular(10),
//       child: Container(
//         width: 150,
//         height: 5,
//         color: Colors.white.withValues(alpha: 0.22),
//         child: AnimatedBuilder(
//           animation: _loop,
//           builder: (_, __) {
//             final t = (_loop.value * 2) % 1.0;
//             return FractionallySizedBox(
//               alignment: Alignment(-1.5 + t * 3.0, 0),
//               widthFactor: 0.4,
//               child: DecoratedBox(
//                 decoration: BoxDecoration(
//                   borderRadius: BorderRadius.circular(10),
//                   gradient: LinearGradient(
//                     colors: [
//                       Colors.white.withValues(alpha: 0.0),
//                       Colors.white,
//                       Colors.white.withValues(alpha: 0.0),
//                     ],
//                   ),
//                 ),
//               ),
//             );
//           },
//         ),
//       ),
//     );
//   }
// }

// class _Glow extends StatelessWidget {
//   const _Glow({required this.size, required this.alpha});
//   final double size;
//   final double alpha;

//   @override
//   Widget build(BuildContext context) => Container(
//         width: size,
//         height: size,
//         decoration: BoxDecoration(
//           shape: BoxShape.circle,
//           gradient: RadialGradient(
//             colors: [
//               Colors.white.withValues(alpha: alpha),
//               Colors.white.withValues(alpha: 0.0),
//             ],
//           ),
//         ),
//       );
// }

// /// Faint dot grid that fades out toward the bottom.
// class _DotGridPainter extends CustomPainter {
//   const _DotGridPainter();

//   @override
//   void paint(Canvas canvas, Size size) {
//     const gap = 30.0;
//     final paint = Paint();
//     for (double y = gap / 2; y < size.height; y += gap) {
//       final fade = (1 - (y / size.height)).clamp(0.0, 1.0);
//       paint.color = Colors.white.withValues(alpha: 0.13 * fade);
//       for (double x = gap / 2; x < size.width; x += gap) {
//         canvas.drawCircle(Offset(x, y), 1.3, paint);
//       }
//     }
//   }

//   @override
//   bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
// }
