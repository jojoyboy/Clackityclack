#import <Cocoa/Cocoa.h>
#import <AVFoundation/AVFoundation.h>
#import <math.h>
#import "SoundSynthesizer.h"

// 1920x1080 at 30 fps for 24 seconds = 720 frames
static const int WIDTH = 1920;
static const int HEIGHT = 1080;
static const int FPS = 30;
static const int DURATION_SEC = 24;
static const int TOTAL_FRAMES = FPS * DURATION_SEC;
static const int SAMPLE_RATE = 44100;
static const int TOTAL_SAMPLES = SAMPLE_RATE * DURATION_SEC;

// Stereo Audio Buffer (Float32)
static float *audioL = NULL;
static float *audioR = NULL;

// Helper to mix an AVAudioPCMBuffer into master stereo track
static void mixAudio(AVAudioPCMBuffer *buf, double startTimeSec, float volume, float pan) {
    if (!buf || buf.frameLength == 0) return;
    int startSample = (int)(startTimeSec * SAMPLE_RATE);
    if (startSample >= TOTAL_SAMPLES) return;
    
    float lGain = volume * fminf(1.0f, 1.0f - pan);
    float rGain = volume * fminf(1.0f, 1.0f + pan);
    
    float *srcL = buf.floatChannelData[0];
    float *srcR = (buf.format.channelCount > 1) ? buf.floatChannelData[1] : srcL;
    float peak = 0.0f;
    for (AVAudioFrameCount sample = 0; sample < buf.frameLength; sample++) {
        peak = fmaxf(peak, fmaxf(fabsf(srcL[sample]), fabsf(srcR[sample])));
    }
    if (peak < 0.001f) return;
    lGain /= peak;
    rGain /= peak;
    
    for (int i = 0; i < (int)buf.frameLength; i++) {
        int idx = startSample + i;
        if (idx >= TOTAL_SAMPLES) break;
        audioL[idx] += srcL[i] * lGain;
        audioR[idx] += srcR[i] * rGain;
    }
}

// Load audio file from path into AVAudioPCMBuffer
static AVAudioPCMBuffer *loadAudio(NSString *path) {
    NSURL *url = [NSURL fileURLWithPath:path];
    NSError *err = nil;
    AVAudioFile *file = [[AVAudioFile alloc] initForReading:url error:&err];
    if (!file) {
        NSLog(@"Warning: Could not load %@", path);
        return nil;
    }
    AVAudioPCMBuffer *buf = [[AVAudioPCMBuffer alloc] initWithPCMFormat:file.processingFormat frameCapacity:(AVAudioFrameCount)file.length];
    [file readIntoBuffer:buf error:&err];
    return buf;
}

// Write master stereo Float32 buffers to 16-bit PCM WAV file
static void saveWav(NSString *outPath) {
    FILE *fp = fopen(outPath.UTF8String, "wb");
    if (!fp) return;
    
    int numChannels = 2;
    int bytesPerSample = 2;
    int byteRate = SAMPLE_RATE * numChannels * bytesPerSample;
    int blockAlign = numChannels * bytesPerSample;
    int dataSize = TOTAL_SAMPLES * blockAlign;
    int chunkSize = 36 + dataSize;
    
    fwrite("RIFF", 1, 4, fp);
    fwrite(&chunkSize, 4, 1, fp);
    fwrite("WAVE", 1, 4, fp);
    fwrite("fmt ", 1, 4, fp);
    int subchunk1Size = 16;
    short audioFormat = 1; // PCM
    short numCh = (short)numChannels;
    int sRate = SAMPLE_RATE;
    short bAlign = (short)blockAlign;
    short bitsPerSample = 16;
    fwrite(&subchunk1Size, 4, 1, fp);
    fwrite(&audioFormat, 2, 1, fp);
    fwrite(&numCh, 2, 1, fp);
    fwrite(&sRate, 4, 1, fp);
    fwrite(&byteRate, 4, 1, fp);
    fwrite(&bAlign, 2, 1, fp);
    fwrite(&bitsPerSample, 2, 1, fp);
    fwrite("data", 1, 4, fp);
    fwrite(&dataSize, 4, 1, fp);
    
    for (int i = 0; i < TOTAL_SAMPLES; i++) {
        // Soft limiting / clipping protection
        float l = fmaxf(-1.0f, fminf(1.0f, audioL[i]));
        float r = fmaxf(-1.0f, fminf(1.0f, audioR[i]));
        short sL = (short)(l * 32767.0f);
        short sR = (short)(r * 32767.0f);
        fwrite(&sL, 2, 1, fp);
        fwrite(&sR, 2, 1, fp);
    }
    fclose(fp);
}

// Drawing Helpers
static void drawTrafficLights(CGContextRef ctx, CGFloat x, CGFloat y) {
    // Red
    CGContextSetRGBFillColor(ctx, 1.0, 0.37, 0.34, 1.0);
    CGContextFillEllipseInRect(ctx, CGRectMake(x, y, 12, 12));
    // Yellow
    CGContextSetRGBFillColor(ctx, 1.0, 0.74, 0.18, 1.0);
    CGContextFillEllipseInRect(ctx, CGRectMake(x + 18, y, 12, 12));
    // Green
    CGContextSetRGBFillColor(ctx, 0.15, 0.79, 0.25, 1.0);
    CGContextFillEllipseInRect(ctx, CGRectMake(x + 36, y, 12, 12));
}

static void drawRoundedRect(CGContextRef ctx, CGRect rect, CGFloat radius, NSColor *fillColor, NSColor *borderColor, CGFloat borderWidth) {
    CGContextSaveGState(ctx);
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:radius yRadius:radius];
    if (fillColor) {
        [fillColor setFill];
        [path fill];
    }
    if (borderColor && borderWidth > 0) {
        [borderColor setStroke];
        path.lineWidth = borderWidth;
        [path stroke];
    }
    CGContextRestoreGState(ctx);
}

static void drawText(NSString *str, CGFloat x, CGFloat y, NSFont *font, NSColor *color) {
    if (!str || str.length == 0) return;
    NSDictionary *attrs = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: color
    };
    [str drawAtPoint:NSMakePoint(x, y) withAttributes:attrs];
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        // 1. Allocate Audio Buffers
        audioL = (float *)calloc(TOTAL_SAMPLES, sizeof(float));
        audioR = (float *)calloc(TOTAL_SAMPLES, sizeof(float));
        
        // 2. Load Real Audio Assets
        AVAudioPCMBuffer *holyPanda = loadAudio(@"Resources/Previews/holy-panda.wav");
        
        AVAudioPCMBuffer *nkKey0 = loadAudio(@"Resources/SoundPacks/NovelKeys Cream (Studio POM)/key_0.wav");
        AVAudioPCMBuffer *nkKey1 = loadAudio(@"Resources/SoundPacks/NovelKeys Cream (Studio POM)/key_1.wav");
        AVAudioPCMBuffer *nkSpace = loadAudio(@"Resources/SoundPacks/NovelKeys Cream (Studio POM)/space.wav");
        
        AVAudioPCMBuffer *modelM = [SoundSynthesizer bufferForProfile:ClackitySoundProfileModelM category:ClackityKeyCategoryStandard isKeyUp:NO variation:0];
        
        AVAudioPCMBuffer *twKey = [SoundSynthesizer bufferForProfile:ClackitySoundProfileTypewriter category:ClackityKeyCategoryStandard isKeyUp:NO variation:0];
        AVAudioPCMBuffer *twBell = [SoundSynthesizer typewriterMarginBellBuffer];
        AVAudioPCMBuffer *twCarriage = [SoundSynthesizer typewriterCarriageReturnBuffer];

        const char *codeText = "AudioEngine *engine = [AudioEngine sharedEngine];\n[engine playKey:HolyPanda withCategory:Enter];";
        int len = (int)strlen(codeText);
        const char *twText = "The sun also rises in the morning over the misty blue hills of Paris";

        mixAudio(holyPanda, 3.9, 0.24, -0.18);
        mixAudio(holyPanda, 4.25, 0.21, 0.12);
        mixAudio(holyPanda, 4.62, 0.23, -0.05);
        mixAudio(holyPanda, 6.6, 0.24, -0.15);
        mixAudio(holyPanda, 6.92, 0.21, 0.15);
        mixAudio(holyPanda, 7.5, 0.22, 0.0);
        mixAudio(holyPanda, 8.0, 0.18, 0.0);

        mixAudio(nkKey0, 9.3, 0.24, -0.12);
        mixAudio(nkKey1, 9.85, 0.24, 0.12);
        mixAudio(nkSpace ?: nkKey0, 10.5, 0.22, 0.0);

        mixAudio(modelM, 11.85, 0.22, -0.12);
        mixAudio(modelM, 12.5, 0.22, 0.12);
        mixAudio(modelM, 13.25, 0.22, 0.0);

        mixAudio(twKey, 14.95, 0.20, -0.12);
        mixAudio(twKey, 15.45, 0.20, 0.12);
        mixAudio(twKey, 16.1, 0.20, 0.0);
        mixAudio(twBell, 17.6, 0.14, 0.0);
        mixAudio(twCarriage, 18.2, 0.18, 0.0);
        
        // Save Audio
        saveWav(@"build.noindex/demo_audio.wav");
        NSLog(@"[VideoGen] Successfully synthesized demo_audio.wav");
        
        // --- 3. VIDEO FRAME RENDERING PIPELINE ---
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        uint8_t *pixelBuffer = (uint8_t *)calloc(WIDTH * HEIGHT * 4, 1);
        CGContextRef ctx = CGBitmapContextCreate(pixelBuffer, WIDTH, HEIGHT, 8, WIDTH * 4, colorSpace, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
        
        NSGraphicsContext *nsCtx = [NSGraphicsContext graphicsContextWithCGContext:ctx flipped:YES];
        [NSGraphicsContext setCurrentContext:nsCtx];
        
        for (int frame = 0; frame < TOTAL_FRAMES; frame++) {
            double time = (double)frame / (double)FPS;
            
            // Clean slate: Charcoal dark gradient (#0a0d14 -> #121824)
            CGContextSaveGState(ctx);
            CGFloat colors[] = {
                0.04, 0.05, 0.08, 1.0,
                0.08, 0.11, 0.17, 1.0
            };
            CGGradientRef grad = CGGradientCreateWithColorComponents(colorSpace, colors, NULL, 2);
            CGContextDrawLinearGradient(ctx, grad, CGPointMake(0, 0), CGPointMake(0, HEIGHT), 0);
            CGGradientRelease(grad);
            
            // Ambient Radial Glow in center
            CGFloat radColors[] = {
                0.0, 0.55, 1.0, 0.12,
                0.0, 0.0, 0.0, 0.0
            };
            CGGradientRef radGrad = CGGradientCreateWithColorComponents(colorSpace, radColors, NULL, 2);
            CGContextDrawRadialGradient(ctx, radGrad, CGPointMake(WIDTH/2, HEIGHT/2 - 50), 0, CGPointMake(WIDTH/2, HEIGHT/2 - 50), 750, 0);
            CGGradientRelease(radGrad);
            CGContextRestoreGState(ctx);
            
            // =========================================================
            // SCENE 1: HERO TITLE & ETHOS (0.0s - 3.5s)
            // =========================================================
            if (time < 3.5) {
                CGFloat alpha = (time < 0.5) ? (time / 0.5) : ((time > 3.0) ? (3.5 - time) / 0.5 : 1.0);
                
                // Keycap Icon
                CGRect keycapRect = CGRectMake(WIDTH/2 - 70, HEIGHT/2 - 250, 140, 140);
                drawRoundedRect(ctx, keycapRect, 32, [NSColor colorWithCalibratedRed:0.12 green:0.16 blue:0.24 alpha:alpha], [NSColor colorWithCalibratedRed:0.0 green:0.6 blue:1.0 alpha:0.5 * alpha], 2.5);
                
                drawText(@"⌘", WIDTH/2 - 32, HEIGHT/2 - 225, [NSFont systemFontOfSize:80 weight:NSFontWeightBold], [NSColor colorWithCalibratedRed:0.2 green:0.75 blue:1.0 alpha:alpha]);
                
                // Title
                drawText(@"Clackity", WIDTH/2 - 185, HEIGHT/2 - 80, [NSFont systemFontOfSize:92 weight:NSFontWeightHeavy], [NSColor colorWithCalibratedWhite:1.0 alpha:alpha]);
                
                // Subtitle
                drawText(@"Acoustic Mechanical Keystroke Feedback for macOS", WIDTH/2 - 365, HEIGHT/2 + 35, [NSFont systemFontOfSize:29 weight:NSFontWeightMedium], [NSColor colorWithCalibratedWhite:0.75 alpha:alpha]);
                
                // Feature Badges
                CGFloat bY = HEIGHT/2 + 120;
                CGFloat bW = 230;
                CGFloat bH = 52;
                
                // Badge 1: < 2.5 MB RAM
                drawRoundedRect(ctx, CGRectMake(WIDTH/2 - 380, bY, bW, bH), 26, [NSColor colorWithCalibratedRed:0.08 green:0.22 blue:0.14 alpha:0.8 * alpha], [NSColor colorWithCalibratedRed:0.18 green:0.80 blue:0.44 alpha:0.8 * alpha], 1.5);
                drawText(@"⚡ < 2.5 MB RAM", WIDTH/2 - 340, bY + 14, [NSFont systemFontOfSize:19 weight:NSFontWeightBold], [NSColor colorWithCalibratedRed:0.28 green:0.95 blue:0.55 alpha:alpha]);
                
                // Badge 2: 0.0% Idle CPU
                drawRoundedRect(ctx, CGRectMake(WIDTH/2 - 115, bY, bW, bH), 26, [NSColor colorWithCalibratedRed:0.08 green:0.18 blue:0.32 alpha:0.8 * alpha], [NSColor colorWithCalibratedRed:0.18 green:0.65 blue:1.0 alpha:0.8 * alpha], 1.5);
                drawText(@"🎯 0.0% Idle CPU", WIDTH/2 - 80, bY + 14, [NSFont systemFontOfSize:19 weight:NSFontWeightBold], [NSColor colorWithCalibratedRed:0.35 green:0.80 blue:1.0 alpha:alpha]);
                
                // Badge 3: 100% Native CoreAudio
                drawRoundedRect(ctx, CGRectMake(WIDTH/2 + 150, bY, bW + 35, bH), 26, [NSColor colorWithCalibratedRed:0.20 green:0.10 blue:0.32 alpha:0.8 * alpha], [NSColor colorWithCalibratedRed:0.70 green:0.35 blue:0.95 alpha:0.8 * alpha], 1.5);
                drawText(@"🎧 100% Native Audio", WIDTH/2 + 175, bY + 14, [NSFont systemFontOfSize:19 weight:NSFontWeightBold], [NSColor colorWithCalibratedRed:0.85 green:0.55 blue:1.0 alpha:alpha]);
            }
            // =========================================================
            // SCENE 2: LIVE CODE TYPING & ACOUSTIC THOCKS (3.5s - 9.0s)
            // =========================================================
            else if (time < 9.0) {
                // Top Tag
                drawRoundedRect(ctx, CGRectMake(WIDTH/2 - 275, 45, 550, 44), 22, [NSColor colorWithCalibratedRed:0.1 green:0.15 blue:0.25 alpha:0.85], [NSColor colorWithCalibratedRed:0.0 green:0.6 blue:1.0 alpha:0.5], 1.5);
                drawText(@"🎙️ Holy Panda (Studio Tactile) · Ultra-Low Latency (<2ms)", WIDTH/2 - 245, 57, [NSFont systemFontOfSize:17 weight:NSFontWeightBold], [NSColor colorWithCalibratedRed:0.3 green:0.85 blue:1.0 alpha:1.0]);
                
                // Editor Window
                CGRect winRect = CGRectMake(240, 120, 1440, 780);
                drawRoundedRect(ctx, winRect, 18, [NSColor colorWithCalibratedRed:0.11 green:0.13 blue:0.18 alpha:0.95], [NSColor colorWithCalibratedWhite:0.25 alpha:0.8], 1.0);
                
                // Titlebar
                drawTrafficLights(ctx, 265, 142);
                drawText(@"Clackity · main.m — Swift / Objective-C Studio", WIDTH/2 - 180, 140, [NSFont systemFontOfSize:15 weight:NSFontWeightMedium], [NSColor colorWithCalibratedWhite:0.7 alpha:1.0]);
                
                // Code Content
                double typeProgress = (time - 3.6) / (7.0 - 3.6);
                int charsToShow = (int)(typeProgress * (double)strlen(codeText));
                if (charsToShow < 0) charsToShow = 0;
                if (charsToShow > (int)strlen(codeText)) charsToShow = (int)strlen(codeText);
                
                NSString *typedStr = [[NSString stringWithUTF8String:codeText] substringToIndex:charsToShow];
                NSArray *lines = [typedStr componentsSeparatedByString:@"\n"];
                
                CGFloat codeY = 210;
                for (int li = 0; li < (int)lines.count; li++) {
                    NSString *line = lines[li];
                    drawText([NSString stringWithFormat:@"%2d", li + 1], 275, codeY, [NSFont monospacedSystemFontOfSize:22 weight:NSFontWeightRegular], [NSColor colorWithCalibratedWhite:0.35 alpha:1.0]);
                    
                    NSColor *codeCol = (li == 0) ? [NSColor colorWithCalibratedRed:0.4 green:0.65 blue:0.45 alpha:1.0] : [NSColor colorWithCalibratedRed:0.3 green:0.75 blue:1.0 alpha:1.0];
                    drawText(line, 335, codeY, [NSFont monospacedSystemFontOfSize:24 weight:NSFontWeightRegular], codeCol);
                    
                    if (li == (int)lines.count - 1) {
                        // Cursor
                        CGFloat curX = 335 + [line sizeWithAttributes:@{NSFontAttributeName: [NSFont monospacedSystemFontOfSize:24 weight:NSFontWeightRegular]}].width + 3;
                        if (((int)(time * 4)) % 2 == 0) {
                            drawRoundedRect(ctx, CGRectMake(curX, codeY + 2, 12, 28), 3, [NSColor colorWithCalibratedRed:0.0 green:0.75 blue:1.0 alpha:1.0], nil, 0);
                        }
                    }
                    codeY += 46;
                }
                
                // Mouse Click Shockwave Ripple at 7.8s - 8.8s
                if (time >= 7.8) {
                    double rAge = time - 7.8;
                    CGFloat rRadius = rAge * 140.0;
                    CGFloat rAlpha = fmaxf(0.0f, 1.0f - (rAge / 1.0f));
                    
                    CGPoint clickPt = CGPointMake(1050, 360);
                    CGContextSaveGState(ctx);
                    CGContextSetRGBStrokeColor(ctx, 0.0, 0.85, 1.0, rAlpha);
                    CGContextSetLineWidth(ctx, 3.5);
                    CGContextStrokeEllipseInRect(ctx, CGRectMake(clickPt.x - rRadius, clickPt.y - rRadius, rRadius * 2, rRadius * 2));
                    
                    // Outer faint echo ring
                    if (rRadius > 30) {
                        CGFloat r2 = rRadius * 0.7;
                        CGContextSetRGBStrokeColor(ctx, 0.2, 0.95, 0.8, rAlpha * 0.6);
                        CGContextSetLineWidth(ctx, 2.0);
                        CGContextStrokeEllipseInRect(ctx, CGRectMake(clickPt.x - r2, clickPt.y - r2, r2 * 2, r2 * 2));
                    }
                    CGContextRestoreGState(ctx);
                    
                    // Mouse Pointer Icon
                    drawText(@"↖", clickPt.x, clickPt.y, [NSFont systemFontOfSize:28 weight:NSFontWeightLight], [NSColor whiteColor]);
                }
                
                // Bottom Live Flow Bar
                drawRoundedRect(ctx, CGRectMake(270, 830, 1380, 50), 12, [NSColor colorWithCalibratedWhite:0.08 alpha:0.9], nil, 0);
                drawText(@"⚡ 1,248 clacks · 112 WPM", 300, 843, [NSFont systemFontOfSize:18 weight:NSFontWeightBold], [NSColor colorWithCalibratedRed:0.25 green:0.85 blue:0.5 alpha:1.0]);
                drawText(@"Spatial Headphone Panning: Active  |  CoreAudio Node Pool: 24 Voices", 920, 845, [NSFont systemFontOfSize:15 weight:NSFontWeightRegular], [NSColor colorWithCalibratedWhite:0.6 alpha:1.0]);
            }
            // =========================================================
            // SCENE 3: SWITCH PROFILES SHOWCASE (9.0s - 14.5s)
            // =========================================================
            else if (time < 14.5) {
                drawText(@"Studio Mechanical Switch Library", WIDTH/2 - 270, 70, [NSFont systemFontOfSize:34 weight:NSFontWeightBold], [NSColor whiteColor]);
                drawText(@"Instant one-click switching between studio recordings and physical synthesizers", WIDTH/2 - 390, 115, [NSFont systemFontOfSize:20 weight:NSFontWeightRegular], [NSColor colorWithCalibratedWhite:0.65 alpha:1.0]);
                
                BOOL isNK = (time < 11.5);
                
                // 3 Switch Cards
                CGFloat cardW = 420;
                CGFloat cardH = 360;
                CGFloat cardY = 180;
                
                // Card 1: NovelKeys Cream
                CGRect c1 = CGRectMake(270, cardY, cardW, cardH);
                NSColor *c1Border = isNK ? [NSColor colorWithCalibratedRed:0.0 green:0.65 blue:1.0 alpha:1.0] : [NSColor colorWithCalibratedWhite:0.25 alpha:1.0];
                drawRoundedRect(ctx, c1, 20, [NSColor colorWithCalibratedRed:0.12 green:0.14 blue:0.20 alpha:0.95], c1Border, isNK ? 3.0 : 1.0);
                drawText(isNK ? @"✅ ACTIVE SWITCH" : @"STUDIO RECORDING", 300, cardY + 30, [NSFont systemFontOfSize:14 weight:NSFontWeightBold], isNK ? [NSColor colorWithCalibratedRed:0.2 green:0.8 blue:1.0 alpha:1.0] : [NSColor colorWithCalibratedWhite:0.5 alpha:1.0]);
                drawText(@"NovelKeys Cream", 300, cardY + 65, [NSFont systemFontOfSize:28 weight:NSFontWeightHeavy], [NSColor whiteColor]);
                drawText(@"Linear · Studio POM Housing", 300, cardY + 105, [NSFont systemFontOfSize:16 weight:NSFontWeightMedium], [NSColor colorWithCalibratedWhite:0.7 alpha:1.0]);
                drawText(@"Ultra-buttery smooth keystroke with deep, muffled bottom-out thock.", 300, cardY + 155, [NSFont systemFontOfSize:16 weight:NSFontWeightRegular], [NSColor colorWithCalibratedWhite:0.65 alpha:1.0]);
                
                // Card 2: IBM Model M
                CGRect c2 = CGRectMake(750, cardY, cardW, cardH);
                NSColor *c2Border = !isNK ? [NSColor colorWithCalibratedRed:0.0 green:0.65 blue:1.0 alpha:1.0] : [NSColor colorWithCalibratedWhite:0.25 alpha:1.0];
                drawRoundedRect(ctx, c2, 20, [NSColor colorWithCalibratedRed:0.12 green:0.14 blue:0.20 alpha:0.95], c2Border, !isNK ? 3.0 : 1.0);
                drawText(!isNK ? @"✅ ACTIVE SWITCH" : @"PHYSICAL MODEL", 780, cardY + 30, [NSFont systemFontOfSize:14 weight:NSFontWeightBold], !isNK ? [NSColor colorWithCalibratedRed:0.2 green:0.8 blue:1.0 alpha:1.0] : [NSColor colorWithCalibratedWhite:0.5 alpha:1.0]);
                drawText(@"IBM Model M", 780, cardY + 65, [NSFont systemFontOfSize:28 weight:NSFontWeightHeavy], [NSColor whiteColor]);
                drawText(@"Buckling Spring · Vintage Steel", 780, cardY + 105, [NSFont systemFontOfSize:16 weight:NSFontWeightMedium], [NSColor colorWithCalibratedWhite:0.7 alpha:1.0]);
                drawText(@"Iconic 1980s helical buckling spring slap with barrel acoustic resonance.", 780, cardY + 155, [NSFont systemFontOfSize:16 weight:NSFontWeightRegular], [NSColor colorWithCalibratedWhite:0.65 alpha:1.0]);
                
                // Card 3: Topre 45g
                CGRect c3 = CGRectMake(1230, cardY, cardW, cardH);
                drawRoundedRect(ctx, c3, 20, [NSColor colorWithCalibratedRed:0.12 green:0.14 blue:0.20 alpha:0.95], [NSColor colorWithCalibratedWhite:0.25 alpha:1.0], 1.0);
                drawText(@"PHYSICAL MODEL", 1260, cardY + 30, [NSFont systemFontOfSize:14 weight:NSFontWeightBold], [NSColor colorWithCalibratedWhite:0.5 alpha:1.0]);
                drawText(@"Topre 45g", 1260, cardY + 65, [NSFont systemFontOfSize:28 weight:NSFontWeightHeavy], [NSColor whiteColor]);
                drawText(@"Electro-Capacitive Silent", 1260, cardY + 105, [NSFont systemFontOfSize:16 weight:NSFontWeightMedium], [NSColor colorWithCalibratedWhite:0.7 alpha:1.0]);
                drawText(@"Plush rubber dome tactile collapse followed by silent slider return.", 1260, cardY + 155, [NSFont systemFontOfSize:16 weight:NSFontWeightRegular], [NSColor colorWithCalibratedWhite:0.65 alpha:1.0]);
                
                // Live Sound Waveform Visualizer Banner below
                CGRect visRect = CGRectMake(270, 600, 1380, 220);
                drawRoundedRect(ctx, visRect, 18, [NSColor colorWithCalibratedRed:0.08 green:0.10 blue:0.15 alpha:0.95], [NSColor colorWithCalibratedWhite:0.25 alpha:0.8], 1.0);
                
                NSString *curTitle = isNK ? @"Auditioning: NovelKeys Cream (POM Linear)" : @"Auditioning: IBM Model M (Buckling Spring)";
                drawText(curTitle, 310, 630, [NSFont systemFontOfSize:22 weight:NSFontWeightBold], [NSColor whiteColor]);
                
                for (int bar = 0; bar < 48; bar++) {
                    int sample = (int)((time - (47 - bar) * 0.025) * SAMPLE_RATE);
                    float peak = 0.0f;
                    for (int offset = 0; offset < SAMPLE_RATE / 40; offset++) {
                        peak = fmaxf(peak, fmaxf(fabsf(audioL[sample + offset]), fabsf(audioR[sample + offset])));
                    }
                    CGFloat barH = 5.0 + fminf(peak * 4.0f, 1.0f) * 100.0;
                    CGFloat barX = 310 + bar * 27;
                    CGFloat barY = 800 - barH;
                    NSColor *barCol = isNK ? [NSColor colorWithCalibratedRed:0.2 green:0.75 blue:1.0 alpha:0.85] : [NSColor colorWithCalibratedRed:1.0 green:0.6 blue:0.2 alpha:0.85];
                    drawRoundedRect(ctx, CGRectMake(barX, barY, 18, barH), 6, barCol, nil, 0);
                }
            }
            // =========================================================
            // SCENE 4: VINTAGE TYPEWRITER MECHANICS (14.5s - 19.5s)
            // =========================================================
            else if (time < 19.5) {
                // Warm retro atmosphere
                drawText(@"📜 Authentic Vintage Typewriter Mechanics", WIDTH/2 - 380, 70, [NSFont systemFontOfSize:34 weight:NSFontWeightBold], [NSColor colorWithCalibratedRed:1.0 green:0.85 blue:0.6 alpha:1.0]);
                drawText(@"Physical line tracking · 1864 Hz Cast-Iron Margin Bell · Platen Carriage Glide", WIDTH/2 - 440, 115, [NSFont systemFontOfSize:20 weight:NSFontWeightRegular], [NSColor colorWithCalibratedWhite:0.7 alpha:1.0]);
                
                // Vintage Typing Sheet Paper Card
                CGRect sheetRect = CGRectMake(320, 180, 1280, 660);
                drawRoundedRect(ctx, sheetRect, 22, [NSColor colorWithCalibratedRed:0.18 green:0.17 blue:0.16 alpha:0.95], [NSColor colorWithCalibratedRed:0.7 green:0.55 blue:0.35 alpha:0.7], 2.0);
                
                drawText(@"ROYAL & UNDERWOOD MECHANICAL PLATEN (1940s)", 370, 220, [NSFont monospacedSystemFontOfSize:16 weight:NSFontWeightBold], [NSColor colorWithCalibratedRed:0.85 green:0.70 blue:0.45 alpha:1.0]);
                
                // Typing Content
                double twProgress = (time - 14.7) / (17.5 - 14.7);
                if (twProgress < 0.0) twProgress = 0.0;
                if (twProgress > 1.0) twProgress = 1.0;
                int twChars = (int)(twProgress * (double)strlen(twText));
                if (twChars < 0) twChars = 0;
                if (twChars > (int)strlen(twText)) twChars = (int)strlen(twText);
                NSString *twTyped = [[NSString stringWithUTF8String:twText] substringToIndex:twChars];
                
                drawText(twTyped, 370, 280, [NSFont fontWithName:@"Times New Roman" size:32] ?: [NSFont systemFontOfSize:32], [NSColor colorWithCalibratedRed:0.95 green:0.92 blue:0.85 alpha:1.0]);
                
                // Margin Bell Trigger Event Banner at 17.6s - 19.5s
                if (time >= 17.6) {
                    CGRect bellBanner = CGRectMake(420, 420, 1080, 95);
                    drawRoundedRect(ctx, bellBanner, 16, [NSColor colorWithCalibratedRed:0.28 green:0.20 blue:0.10 alpha:0.9], [NSColor colorWithCalibratedRed:1.0 green:0.78 blue:0.25 alpha:0.9], 2.0);
                    
                    drawText(@"Margin bell", 460, 442, [NSFont systemFontOfSize:24 weight:NSFontWeightBold], [NSColor colorWithCalibratedRed:1.0 green:0.85 blue:0.3 alpha:1.0]);
                    drawText(@"Acoustic cast-iron chime (1864 Hz Bb6 with 410 Hz body coupling)", 460, 475, [NSFont systemFontOfSize:16 weight:NSFontWeightRegular], [NSColor colorWithCalibratedWhite:0.8 alpha:1.0]);
                }
                
                // Carriage Return Glide Event Banner at 18.2s - 19.5s
                if (time >= 18.2) {
                    CGRect crBanner = CGRectMake(420, 535, 1080, 95);
                    drawRoundedRect(ctx, crBanner, 16, [NSColor colorWithCalibratedRed:0.12 green:0.22 blue:0.16 alpha:0.9], [NSColor colorWithCalibratedRed:0.3 green:0.85 blue:0.5 alpha:0.9], 2.0);
                    
                    drawText(@"Carriage return", 460, 557, [NSFont systemFontOfSize:24 weight:NSFontWeightBold], [NSColor colorWithCalibratedRed:0.4 green:0.95 blue:0.6 alpha:1.0]);
                    drawText(@"Whirrr-ka-chunk! Mechanical platen ratchet, rail slide, and bumper impact", 460, 590, [NSFont systemFontOfSize:16 weight:NSFontWeightRegular], [NSColor colorWithCalibratedWhite:0.8 alpha:1.0]);
                }
                
                // Column Counter
                int col = (time < 18.2) ? fmin(72, (int)(twProgress * 72)) : 0;
                drawText([NSString stringWithFormat:@"Platen Column: %d / 72", col], 370, 780, [NSFont monospacedSystemFontOfSize:18 weight:NSFontWeightMedium], [NSColor colorWithCalibratedWhite:0.6 alpha:1.0]);
            }
            // =========================================================
            // SCENE 5: FEATURE SUITE & OUTRO (19.5s - 24.0s)
            // =========================================================
            else {
                drawText(@"Complete Acoustic & Tactile Innovations Suite", WIDTH/2 - 410, 60, [NSFont systemFontOfSize:34 weight:NSFontWeightBold], [NSColor whiteColor]);
                
                // 4 Innovation Cards
                CGFloat gW = 660;
                CGFloat gH = 150;
                
                // 1. Parametric EQ
                drawRoundedRect(ctx, CGRectMake(260, 130, gW, gH), 16, [NSColor colorWithCalibratedRed:0.12 green:0.15 blue:0.22 alpha:0.9], [NSColor colorWithCalibratedWhite:0.25 alpha:1.0], 1.0);
                drawText(@"🎛️ CoreAudio Parametric Equalizer", 290, 155, [NSFont systemFontOfSize:20 weight:NSFontWeightBold], [NSColor colorWithCalibratedRed:0.3 green:0.8 blue:1.0 alpha:1.0]);
                drawText(@"Real-time low-shelf & high-shelf DSP filters (PE Foam Thock ↔ Brass Plate Clack).", 290, 190, [NSFont systemFontOfSize:15 weight:NSFontWeightRegular], [NSColor colorWithCalibratedWhite:0.7 alpha:1.0]);
                
                // 2. Key-Pitch Row Mapping & Krytox
                drawRoundedRect(ctx, CGRectMake(980, 130, gW, gH), 16, [NSColor colorWithCalibratedRed:0.12 green:0.15 blue:0.22 alpha:0.9], [NSColor colorWithCalibratedWhite:0.25 alpha:1.0], 1.0);
                drawText(@"📐 Key-Pitch Row Mapping & Krytox Lube", 1010, 155, [NSFont systemFontOfSize:20 weight:NSFontWeightBold], [NSColor colorWithCalibratedRed:0.3 green:0.8 blue:1.0 alpha:1.0]);
                drawText(@"Keyboard geometry pitch contours + CoreAudio DSP friction scratch dampening.", 1010, 190, [NSFont systemFontOfSize:15 weight:NSFontWeightRegular], [NSColor colorWithCalibratedWhite:0.7 alpha:1.0]);
                
                // 3. Trackpad Haptics
                drawRoundedRect(ctx, CGRectMake(260, 305, gW, gH), 16, [NSColor colorWithCalibratedRed:0.12 green:0.15 blue:0.22 alpha:0.9], [NSColor colorWithCalibratedWhite:0.25 alpha:1.0], 1.0);
                drawText(@"📳 MacBook Trackpad Haptics (Force Touch)", 290, 330, [NSFont systemFontOfSize:20 weight:NSFontWeightBold], [NSColor colorWithCalibratedRed:0.3 green:0.8 blue:1.0 alpha:1.0]);
                drawText(@"Microsecond mechanical deck resonance under your palms as you type or click.", 290, 365, [NSFont systemFontOfSize:15 weight:NSFontWeightRegular], [NSColor colorWithCalibratedWhite:0.7 alpha:1.0]);
                
                // 4. App-Specific Auto-Switching
                drawRoundedRect(ctx, CGRectMake(980, 305, gW, gH), 16, [NSColor colorWithCalibratedRed:0.12 green:0.15 blue:0.22 alpha:0.9], [NSColor colorWithCalibratedWhite:0.25 alpha:1.0], 1.0);
                drawText(@"🎯 App-Specific Switch Auto-Switching", 1010, 330, [NSFont systemFontOfSize:20 weight:NSFontWeightBold], [NSColor colorWithCalibratedRed:0.3 green:0.8 blue:1.0 alpha:1.0]);
                drawText(@"Auto-switches profiles for Xcode, Terminal, Obsidian, Slack, & Safari.", 1010, 365, [NSFont systemFontOfSize:15 weight:NSFontWeightRegular], [NSColor colorWithCalibratedWhite:0.7 alpha:1.0]);
                
                // Terminal / CLI Section
                CGRect termRect = CGRectMake(360, 485, 1200, 320);
                drawRoundedRect(ctx, termRect, 18, [NSColor colorWithCalibratedRed:0.06 green:0.08 blue:0.12 alpha:0.98], [NSColor colorWithCalibratedRed:0.0 green:0.6 blue:1.0 alpha:0.5], 1.5);
                drawTrafficLights(ctx, 385, 507);
                drawText(@"Terminal — clack CLI & Homebrew Installation", WIDTH/2 - 180, 505, [NSFont systemFontOfSize:15 weight:NSFontWeightMedium], [NSColor colorWithCalibratedWhite:0.7 alpha:1.0]);
                
                drawText(@"$ brew tap jojoyboy/clackity", 400, 560, [NSFont monospacedSystemFontOfSize:23 weight:NSFontWeightRegular], [NSColor colorWithCalibratedRed:0.3 green:0.85 blue:1.0 alpha:1.0]);
                drawText(@"$ brew install --cask clackity", 400, 605, [NSFont monospacedSystemFontOfSize:23 weight:NSFontWeightRegular], [NSColor colorWithCalibratedRed:0.3 green:0.85 blue:1.0 alpha:1.0]);
                drawText(@"==> Successfully installed Clackity into /Applications", 400, 650, [NSFont monospacedSystemFontOfSize:20 weight:NSFontWeightRegular], [NSColor colorWithCalibratedRed:0.3 green:0.95 blue:0.5 alpha:1.0]);
                drawText(@"$ clack switch \"Holy Panda\"  # Control via terminal & Raycast", 400, 695, [NSFont monospacedSystemFontOfSize:23 weight:NSFontWeightRegular], [NSColor colorWithCalibratedWhite:0.9 alpha:1.0]);
                drawText(@"⚡ Switched Clackity profile to: Holy Panda", 400, 740, [NSFont monospacedSystemFontOfSize:20 weight:NSFontWeightRegular], [NSColor colorWithCalibratedRed:0.3 green:0.95 blue:0.5 alpha:1.0]);
                
                // Footer
                drawText(@"Free & Open Source  ·  github.com/jojoyboy/Clackityclack  ·  GNU GPLv3", WIDTH/2 - 380, 840, [NSFont systemFontOfSize:20 weight:NSFontWeightMedium], [NSColor colorWithCalibratedWhite:0.7 alpha:1.0]);
            }
            
            // Pipe raw RGBA pixel buffer to stdout
            fwrite(pixelBuffer, 1, WIDTH * HEIGHT * 4, stdout);
        }
        
        CGContextRelease(ctx);
        CGColorSpaceRelease(colorSpace);
        free(pixelBuffer);
        free(audioL);
        free(audioR);
    }
    return 0;
}
