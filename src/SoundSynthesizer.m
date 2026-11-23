#import "SoundSynthesizer.h"
#import <math.h>

typedef struct {
    double fPlate;      // Plate/case boom (Hz)
    double aPlate;      // Plate amplitude
    double dPlate;      // Plate decay rate
    
    double fCap;        // Keycap cavity resonance (Hz)
    double aCap;        // Keycap amplitude
    double dCap;        // Keycap decay rate
    
    double fStem;       // Stem pole impact resonance (Hz)
    double aStem;       // Stem amplitude
    double dStem;       // Stem decay rate
    
    double fAir;        // Upper air reflection (Hz)
    double aAir;        // Air reflection amplitude
    double dAir;        // Air decay rate
    
    double noiseGain;   // Rail friction noise
    double noiseDecay;  // Noise decay rate
    
    double clickDelay;  // Click bar / leaf delay in seconds (0 for linear)
    double clickFreq;   // Click frequency (Hz)
    double clickGain;   // Click amplitude
    
    double springPing;  // Spring reverberation gain
    double springFreq;  // Spring resonance frequency
    
    double duration;    // Buffer duration in seconds
    double masterGain;  // Overall loudness normalization
} SwitchAcoustics;

@implementation SoundSynthesizer

+ (NSArray<NSNumber *> *)allProfiles {
    return @[
        @(ClackitySoundProfileGateronOilKing),
        @(ClackitySoundProfileBobaU4T),
        @(ClackitySoundProfileHolyPanda),
        @(ClackitySoundProfileAlpaca),
        @(ClackitySoundProfileTopre),
        @(ClackitySoundProfileNKCream),
        @(ClackitySoundProfileCherryMXBlack),
        @(ClackitySoundProfileKailhBoxWhite),
        @(ClackitySoundProfileModelM),
        @(ClackitySoundProfileAppleALPS),
        @(ClackitySoundProfileTypewriter),
        @(ClackitySoundProfilePop)
    ];
}

+ (NSString *)nameForProfile:(ClackitySoundProfile)profile {
    switch (profile) {
        case ClackitySoundProfileGateronOilKing: return @"Gateron Oil King (Deep Thock)";
        case ClackitySoundProfileBobaU4T:        return @"Boba U4T (Thocky Tactile)";
        case ClackitySoundProfileHolyPanda:      return @"Holy Panda (Snappy Pop)";
        case ClackitySoundProfileAlpaca:         return @"Alpaca V2 (Marbly Linear)";
        case ClackitySoundProfileTopre:          return @"Topre 45g (Silent Electro-Capacitive)";
        case ClackitySoundProfileNKCream:        return @"NovelKeys Cream (POM Clack)";
        case ClackitySoundProfileCherryMXBlack:  return @"Cherry MX Black (Vintage Nylon)";
        case ClackitySoundProfileKailhBoxWhite:  return @"Kailh Box White (Click-Bar)";
        case ClackitySoundProfileModelM:         return @"IBM Model M (Buckling Spring)";
        case ClackitySoundProfileAppleALPS:      return @"Apple M0115 (ALPS Cream Damped)";
        case ClackitySoundProfileTypewriter:     return @"Underwood Vintage Typewriter";
        case ClackitySoundProfilePop:            return @"Modern Pop (ASMR Bubble)";
    }
}

+ (NSString *)subtitleForProfile:(ClackitySoundProfile)profile {
    switch (profile) {
        case ClackitySoundProfileGateronOilKing: return @"Ultra-deep, lubricated buttery thock";
        case ClackitySoundProfileBobaU4T:        return @"Heavy tactile D-bump with thick PBT acoustic";
        case ClackitySoundProfileHolyPanda:      return @"Snappy tactile bump with distinct polycarbonate pop";
        case ClackitySoundProfileAlpaca:         return @"Glass-like marbly acoustic with clean highs";
        case ClackitySoundProfileTopre:          return @"Muted, pillowy rubber dome sound (HHKB style)";
        case ClackitySoundProfileNKCream:        return @"Distinctive self-lubricating POM housing clack";
        case ClackitySoundProfileCherryMXBlack:  return @"Authoritative retro bottom-out in nylon casing";
        case ClackitySoundProfileKailhBoxWhite:  return @"Crisp dual-direction click-bar snap";
        case ClackitySoundProfileModelM:         return @"Iconic 1980s buckling spring & steel plate";
        case ClackitySoundProfileAppleALPS:      return @"Classic dampened tactile Apple keyboard sound";
        case ClackitySoundProfileTypewriter:     return @"Mechanical type-hammer strike and platen clatter";
        case ClackitySoundProfilePop:            return @"Snappy, rounded bubble pop feedback";
    }
}

+ (SwitchAcoustics)acousticsForProfile:(ClackitySoundProfile)profile {
    SwitchAcoustics a = {0};
    
    switch (profile) {
        case ClackitySoundProfileGateronOilKing: // Deep Thock Linear
            a.fPlate = 260.0; a.aPlate = 0.85; a.dPlate = 68.0;
            a.fCap   = 520.0; a.aCap   = 0.70; a.dCap   = 95.0;
            a.fStem  = 1040.0;a.aStem  = 0.38; a.dStem  = 130.0;
            a.fAir   = 2400.0;a.aAir   = 0.14; a.dAir   = 200.0;
            a.noiseGain = 0.22; a.noiseDecay = 140.0;
            a.duration = 0.065; a.masterGain = 1.05;
            break;
            
        case ClackitySoundProfileBobaU4T: // Thocky Tactile
            a.fPlate = 310.0; a.aPlate = 0.80; a.dPlate = 75.0;
            a.fCap   = 620.0; a.aCap   = 0.75; a.dCap   = 100.0;
            a.fStem  = 1240.0;a.aStem  = 0.48; a.dStem  = 125.0;
            a.fAir   = 2800.0;a.aAir   = 0.18; a.dAir   = 190.0;
            a.noiseGain = 0.25; a.noiseDecay = 135.0;
            a.duration = 0.060; a.masterGain = 1.05;
            break;
            
        case ClackitySoundProfileHolyPanda: // Snappy Pop Tactile
            a.fPlate = 380.0; a.aPlate = 0.75; a.dPlate = 82.0;
            a.fCap   = 760.0; a.aCap   = 0.80; a.dCap   = 110.0;
            a.fStem  = 1520.0;a.aStem  = 0.55; a.dStem  = 115.0;
            a.fAir   = 3200.0;a.aAir   = 0.22; a.dAir   = 180.0;
            a.noiseGain = 0.28; a.noiseDecay = 140.0;
            a.duration = 0.055; a.masterGain = 1.02;
            break;
            
        case ClackitySoundProfileAlpaca: // Marbly Linear
            a.fPlate = 350.0; a.aPlate = 0.70; a.dPlate = 88.0;
            a.fCap   = 700.0; a.aCap   = 0.85; a.dCap   = 115.0;
            a.fStem  = 1650.0;a.aStem  = 0.50; a.dStem  = 125.0;
            a.fAir   = 3600.0;a.aAir   = 0.26; a.dAir   = 175.0;
            a.noiseGain = 0.18; a.noiseDecay = 160.0;
            a.duration = 0.052; a.masterGain = 1.00;
            break;
            
        case ClackitySoundProfileTopre: // Electro-Capacitive Silent (HHKB)
            a.fPlate = 240.0; a.aPlate = 0.90; a.dPlate = 90.0;
            a.fCap   = 480.0; a.aCap   = 0.60; a.dCap   = 120.0;
            a.fStem  = 850.0; a.aStem  = 0.32; a.dStem  = 150.0;
            a.fAir   = 1900.0;a.aAir   = 0.10; a.dAir   = 220.0;
            a.noiseGain = 0.15; a.noiseDecay = 170.0;
            a.duration = 0.052; a.masterGain = 1.00;
            break;
            
        case ClackitySoundProfileNKCream: // POM Creamy Linear
            a.fPlate = 360.0; a.aPlate = 0.75; a.dPlate = 80.0;
            a.fCap   = 720.0; a.aCap   = 0.75; a.dCap   = 105.0;
            a.fStem  = 1450.0;a.aStem  = 0.48; a.dStem  = 120.0;
            a.fAir   = 3000.0;a.aAir   = 0.20; a.dAir   = 185.0;
            a.noiseGain = 0.30; a.noiseDecay = 120.0; // characteristic POM slider texture
            a.duration = 0.056; a.masterGain = 1.02;
            break;
            
        case ClackitySoundProfileCherryMXBlack: // Vintage Hyperglide Nylon
            a.fPlate = 300.0; a.aPlate = 0.85; a.dPlate = 75.0;
            a.fCap   = 600.0; a.aCap   = 0.70; a.dCap   = 98.0;
            a.fStem  = 1200.0;a.aStem  = 0.42; a.dStem  = 125.0;
            a.fAir   = 2600.0;a.aAir   = 0.16; a.dAir   = 195.0;
            a.noiseGain = 0.24; a.noiseDecay = 145.0;
            a.duration = 0.058; a.masterGain = 1.05;
            break;
            
        case ClackitySoundProfileKailhBoxWhite: // Precision Click-Bar
            a.fPlate = 440.0; a.aPlate = 0.60; a.dPlate = 90.0;
            a.fCap   = 880.0; a.aCap   = 0.65; a.dCap   = 115.0;
            a.fStem  = 1800.0;a.aStem  = 0.45; a.dStem  = 130.0;
            a.fAir   = 4200.0;a.aAir   = 0.25; a.dAir   = 175.0;
            a.noiseGain = 0.22; a.noiseDecay = 135.0;
            a.clickDelay = 0.0025; a.clickFreq = 3800.0; a.clickGain = 1.10; // crisp click bar snap
            a.duration = 0.050; a.masterGain = 1.00;
            break;
            
        case ClackitySoundProfileModelM: // IBM Buckling Spring
            a.fPlate = 360.0; a.aPlate = 0.75; a.dPlate = 68.0;
            a.fCap   = 740.0; a.aCap   = 0.65; a.dCap   = 92.0;
            a.fStem  = 1480.0;a.aStem  = 0.50; a.dStem  = 115.0;
            a.fAir   = 3200.0;a.aAir   = 0.25; a.dAir   = 150.0;
            a.noiseGain = 0.32; a.noiseDecay = 105.0;
            a.clickDelay = 0.0028; a.clickFreq = 3100.0; a.clickGain = 1.15; // buckle snap
            a.springPing = 0.35;   a.springFreq = 2400.0; // helical spring ring
            a.duration = 0.082; a.masterGain = 1.05;
            break;
            
        case ClackitySoundProfileAppleALPS: // Vintage Apple Extended Keyboard (ALPS Cream)
            a.fPlate = 290.0; a.aPlate = 0.80; a.dPlate = 72.0;
            a.fCap   = 580.0; a.aCap   = 0.70; a.dCap   = 95.0;
            a.fStem  = 1160.0;a.aStem  = 0.45; a.dStem  = 120.0;
            a.fAir   = 2400.0;a.aAir   = 0.16; a.dAir   = 185.0;
            a.noiseGain = 0.26; a.noiseDecay = 130.0;
            a.duration = 0.060; a.masterGain = 1.02;
            break;
            
        case ClackitySoundProfileTypewriter: // Underwood Typewriter
            a.fPlate = 680.0; a.aPlate = 0.65; a.dPlate = 55.0;
            a.fCap   = 1600.0;a.aCap   = 0.80; a.dCap   = 80.0;
            a.fStem  = 2800.0;a.aStem  = 0.60; a.dStem  = 100.0;
            a.fAir   = 4800.0;a.aAir   = 0.30; a.dAir   = 130.0;
            a.noiseGain = 0.50; a.noiseDecay = 85.0;
            a.springPing = 0.40; a.springFreq = 3600.0;
            a.duration = 0.088; a.masterGain = 1.05;
            break;
            
        case ClackitySoundProfilePop: // ASMR Bubble Pop
            a.fPlate = 540.0; a.aPlate = 0.95; a.dPlate = 90.0;
            a.fCap   = 1200.0;a.aCap   = 0.55; a.dCap   = 130.0;
            a.fStem  = 2200.0;a.aStem  = 0.25; a.dStem  = 180.0;
            a.fAir   = 3600.0;a.aAir   = 0.08; a.dAir   = 240.0;
            a.noiseGain = 0.08; a.noiseDecay = 200.0;
            a.duration = 0.045; a.masterGain = 1.00;
            break;
    }
    
    return a;
}

+ (AVAudioPCMBuffer *)bufferForProfile:(ClackitySoundProfile)profile
                              category:(ClackityKeyCategory)category
                               isKeyUp:(BOOL)isKeyUp
                             variation:(NSInteger)variation {
    const double sampleRate = 44100.0;
    SwitchAcoustics a = [self acousticsForProfile:profile];
    
    // Key Category Acoustic Modifiers
    switch (category) {
        case ClackityKeyCategorySpacebar:
            // Massive stabilizer wire & hollow 6.25u keycap bar acoustics
            a.fPlate *= 0.72;
            a.fCap *= 0.78;
            a.aPlate *= 1.30;
            a.noiseGain *= 1.35;
            a.duration *= 1.35;
            a.masterGain *= 1.20;
            break;
            
        case ClackityKeyCategoryEnter:
            // 2.25u keycap chamber tone with punchy tactile bottom-out
            a.fPlate *= 0.78;
            a.fCap *= 0.82;
            a.aPlate *= 1.10;
            a.duration *= 1.18;
            a.masterGain *= 1.05;
            break;
            
        case ClackityKeyCategoryBackspace:
            // 2u keycap snappy clack with quick transient
            a.fPlate *= 1.16;
            a.fCap *= 1.12;
            a.fStem *= 1.15;
            a.duration *= 0.88;
            break;
            
        case ClackityKeyCategoryModifier:
            // Slightly softer volume for modifier keys
            a.fPlate *= 0.92;
            a.masterGain *= 0.78;
            break;
            
        case ClackityKeyCategoryMouseLeft:
            // Snappy microswitch click
            a.fPlate = 1350.0; a.aPlate = 0.50; a.dPlate = 180.0;
            a.fCap   = 2900.0; a.aCap   = 0.40; a.dCap   = 220.0;
            a.fStem  = 4800.0; a.aStem  = 0.25; a.dStem  = 260.0;
            a.noiseGain = 0.22; a.noiseDecay = 240.0;
            a.clickGain = 0.0; a.springPing = 0.0;
            a.duration = 0.024; a.masterGain = 0.72;
            break;
            
        case ClackityKeyCategoryMouseRight:
            // Slightly lower pitch right click
            a.fPlate = 1120.0; a.aPlate = 0.50; a.dPlate = 170.0;
            a.fCap   = 2400.0; a.aCap   = 0.40; a.dCap   = 210.0;
            a.fStem  = 4100.0; a.aStem  = 0.25; a.dStem  = 250.0;
            a.noiseGain = 0.22; a.noiseDecay = 240.0;
            a.clickGain = 0.0; a.springPing = 0.0;
            a.duration = 0.026; a.masterGain = 0.68;
            break;
            
        case ClackityKeyCategoryMouseScroll:
            // Discrete mechanical scroll detent
            a.fPlate = 1750.0; a.aPlate = 0.40; a.dPlate = 240.0;
            a.fCap   = 3600.0; a.aCap   = 0.30; a.dCap   = 280.0;
            a.fStem  = 5400.0; a.aStem  = 0.15; a.dStem  = 300.0;
            a.noiseGain = 0.18; a.noiseDecay = 300.0;
            a.clickGain = 0.0; a.springPing = 0.0;
            a.duration = 0.014; a.masterGain = 0.45;
            break;
            
        default:
            break;
    }
    
    // KeyUp adjustments (Top-housing return stroke impact)
    if (isKeyUp) {
        a.fPlate *= 1.35;
        a.fCap   *= 1.30;
        a.fStem  *= 1.25;
        a.aPlate *= 0.45;
        a.aCap   *= 0.65;
        a.masterGain *= 0.65;
        a.duration *= 0.65;
        a.dPlate *= 1.30;
        a.clickGain *= 0.40; // softer return click
    }
    
    // Micro-pitch & micro-frequency variation across strikes (±3%)
    double pitchMultiplier = 1.0 + ((double)variation - 1.5) * 0.024;
    a.fPlate *= pitchMultiplier;
    a.fCap   *= pitchMultiplier;
    a.fStem  *= pitchMultiplier;
    
    AVAudioFormat *format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:sampleRate channels:1];
    AVAudioFrameCount frameCount = (AVAudioFrameCount)(sampleRate * a.duration);
    AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:frameCount];
    buffer.frameLength = frameCount;
    
    float *channelData = buffer.floatChannelData[0];
    
    // Procedural multi-formant physical acoustic synthesis loop
    for (AVAudioFrameCount i = 0; i < frameCount; i++) {
        double t = (double)i / sampleRate;
        
        // Fast 0.3ms attack envelope
        double attack = (t < 0.0003) ? (t / 0.0003) : 1.0;
        
        // Dynamic bottom-out pitch slump (modeling plastic/metal compression impact)
        double instPlate = a.fPlate * (1.0 + 0.35 * exp(-140.0 * t));
        double instCap   = a.fCap   * (1.0 + 0.18 * exp(-100.0 * t));
        double instStem  = a.fStem  * (1.0 + 0.10 * exp(-80.0 * t));
        
        // Multi-formant harmonic resonances
        double tonePlate = sin(2.0 * M_PI * instPlate * t) * a.aPlate * exp(-a.dPlate * t);
        double toneCap   = sin(2.0 * M_PI * instCap   * t) * a.aCap   * exp(-a.dCap   * t);
        double toneStem  = sin(2.0 * M_PI * instStem  * t) * a.aStem  * exp(-a.dStem  * t);
        double toneAir   = sin(2.0 * M_PI * a.fAir    * t) * a.aAir   * exp(-a.dAir   * t);
        
        // Stem slider rail friction noise burst
        double noiseVal = ((double)arc4random() / 0xFFFFFFFF * 2.0 - 1.0);
        double noiseBurst = noiseVal * a.noiseGain * exp(-a.noiseDecay * t);
        
        // Mechanical click-bar / leaf snap transient
        double clickSnap = 0.0;
        if (a.clickGain > 0.01 && t >= a.clickDelay && t < a.clickDelay + 0.007) {
            double dt = t - a.clickDelay;
            clickSnap = sin(2.0 * M_PI * a.clickFreq * dt) * exp(-320.0 * dt) * a.clickGain;
        }
        
        // Helical spring reverberation ping (Model M / vintage springs)
        double springSound = 0.0;
        if (a.springPing > 0.01 && t > 0.002) {
            double st = t - 0.002;
            springSound = sin(2.0 * M_PI * a.springFreq * st) * exp(-45.0 * st) * a.springPing;
        }
        
        // Mix all physical acoustic components
        double sample = (tonePlate + toneCap + toneStem + toneAir + noiseBurst + clickSnap + springSound) * attack * a.masterGain;
        
        // Soft analog saturation (tanh-like soft curve)
        if (sample > 1.0) sample = 1.0;
        else if (sample < -1.0) sample = -1.0;
        
        channelData[i] = (float)sample;
    }
    
    return buffer;
}

@end
