#import <Cocoa/Cocoa.h>

void drawAppIcon(CGContextRef ctx, CGFloat size) {
    // Coordinate space is (0, 0) to (size, size)
    CGFloat scale = size / 1024.0;
    
    // 1. Background Rounded Squircle
    CGFloat margin = 80.0 * scale;
    CGFloat cornerRadius = 224.0 * scale;
    CGRect squircleRect = CGRectMake(margin, margin, size - margin * 2, size - margin * 2);
    
    CGContextSaveGState(ctx);
    
    // Drop shadow
    CGContextSetShadowWithColor(ctx, CGSizeMake(0, -12 * scale), 28 * scale, [NSColor colorWithCalibratedWhite:0.0 alpha:0.45].CGColor);
    
    NSBezierPath *squirclePath = [NSBezierPath bezierPathWithRoundedRect:squircleRect xRadius:cornerRadius yRadius:cornerRadius];
    CGPathRef cgSquircle = [squirclePath CGPath];
    CGContextAddPath(ctx, cgSquircle);
    CGContextClip(ctx);
    
    // Background gradient (Dark deep space slate)
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGFloat bgColors[] = {
        0.14, 0.16, 0.22, 1.0, // Top slate
        0.07, 0.08, 0.11, 1.0  // Bottom deep obsidian
    };
    CGGradientRef bgGrad = CGGradientCreateWithColorComponents(colorSpace, bgColors, NULL, 2);
    CGContextDrawLinearGradient(ctx, bgGrad, CGPointMake(size/2, size - margin), CGPointMake(size/2, margin), 0);
    CGGradientRelease(bgGrad);
    
    // Subtle border stroke
    CGContextSetStrokeColorWithColor(ctx, [NSColor colorWithCalibratedWhite:1.0 alpha:0.12].CGColor);
    CGContextSetLineWidth(ctx, 4.0 * scale);
    CGContextAddPath(ctx, cgSquircle);
    CGContextStrokePath(ctx);
    
    CGContextRestoreGState(ctx);
    
    // 2. Sound Waves (Tactile acoustic rings radiating behind switch)
    CGContextSaveGState(ctx);
    CGPoint center = CGPointMake(size / 2.0, size / 2.0 + 10.0 * scale);
    CGFloat waveRadii[] = { 320.0 * scale, 380.0 * scale };
    for (int i = 0; i < 2; i++) {
        CGFloat r = waveRadii[i];
        CGRect arcRect = CGRectMake(center.x - r, center.y - r, r * 2, r * 2);
        CGContextSetStrokeColorWithColor(ctx, [NSColor colorWithCalibratedRed:0.0 green:0.82 blue:1.0 alpha:(0.14 - i * 0.05)].CGColor);
        CGContextSetLineWidth(ctx, (6.0 - i * 2.0) * scale);
        CGContextAddArc(ctx, center.x, center.y, r, -M_PI * 0.25, M_PI * 0.25, 0);
        CGContextStrokePath(ctx);
        CGContextAddArc(ctx, center.x, center.y, r, M_PI * 0.75, M_PI * 1.25, 0);
        CGContextStrokePath(ctx);
    }
    CGContextRestoreGState(ctx);
    
    // 3. Mechanical Switch Outer Housing (Smoky translucent polycarbonate)
    CGFloat housingSize = 480.0 * scale;
    CGRect housingRect = CGRectMake(center.x - housingSize/2.0, center.y - housingSize/2.0, housingSize, housingSize);
    
    CGContextSaveGState(ctx);
    CGContextSetShadowWithColor(ctx, CGSizeMake(0, -10 * scale), 24 * scale, [NSColor colorWithCalibratedWhite:0.0 alpha:0.6].CGColor);
    
    NSBezierPath *housingPath = [NSBezierPath bezierPathWithRoundedRect:housingRect xRadius:48.0 * scale yRadius:48.0 * scale];
    CGPathRef cgHousing = [housingPath CGPath];
    CGContextAddPath(ctx, cgHousing);
    CGContextClip(ctx);
    
    CGFloat housingColors[] = {
        0.24, 0.27, 0.35, 0.95,
        0.13, 0.15, 0.20, 0.95
    };
    CGGradientRef housingGrad = CGGradientCreateWithColorComponents(colorSpace, housingColors, NULL, 2);
    CGContextDrawLinearGradient(ctx, housingGrad, CGPointMake(center.x, housingRect.origin.y + housingSize), CGPointMake(center.x, housingRect.origin.y), 0);
    CGGradientRelease(housingGrad);
    
    // Housing inner bevel highlight
    CGContextSetStrokeColorWithColor(ctx, [NSColor colorWithCalibratedRed:0.0 green:0.82 blue:1.0 alpha:0.35].CGColor);
    CGContextSetLineWidth(ctx, 3.5 * scale);
    CGContextAddPath(ctx, cgHousing);
    CGContextStrokePath(ctx);
    CGContextRestoreGState(ctx);
    
    // 4. Center Stem Well (Circle cavity)
    CGFloat wellRadius = 160.0 * scale;
    CGRect wellRect = CGRectMake(center.x - wellRadius, center.y - wellRadius, wellRadius * 2, wellRadius * 2);
    CGContextSaveGState(ctx);
    CGContextSetFillColorWithColor(ctx, [NSColor colorWithCalibratedRed:0.08 green:0.09 blue:0.13 alpha:1.0].CGColor);
    CGContextFillEllipseInRect(ctx, wellRect);
    CGContextSetStrokeColorWithColor(ctx, [NSColor colorWithCalibratedWhite:1.0 alpha:0.08].CGColor);
    CGContextSetLineWidth(ctx, 3.0 * scale);
    CGContextStrokeEllipseInRect(ctx, wellRect);
    CGContextRestoreGState(ctx);
    
    // 5. MX Mechanical Cross Stem (+) in Electric Cyan / Teal
    CGFloat stemArmWidth = 46.0 * scale;
    CGFloat stemArmLength = 190.0 * scale;
    CGFloat stemRadius = 12.0 * scale;
    
    CGRect stemHoriz = CGRectMake(center.x - stemArmLength/2.0, center.y - stemArmWidth/2.0, stemArmLength, stemArmWidth);
    CGRect stemVert  = CGRectMake(center.x - stemArmWidth/2.0, center.y - stemArmLength/2.0, stemArmWidth, stemArmLength);
    
    CGContextSaveGState(ctx);
    CGContextSetShadowWithColor(ctx, CGSizeMake(0, -4 * scale), 16 * scale, [NSColor colorWithCalibratedRed:0.0 green:0.82 blue:1.0 alpha:0.55].CGColor);
    
    NSBezierPath *hArm = [NSBezierPath bezierPathWithRoundedRect:stemHoriz xRadius:stemRadius yRadius:stemRadius];
    NSBezierPath *vArm = [NSBezierPath bezierPathWithRoundedRect:stemVert xRadius:stemRadius yRadius:stemRadius];
    
    [hArm appendBezierPath:vArm];
    CGPathRef cgStem = [hArm CGPath];
    CGContextAddPath(ctx, cgStem);
    CGContextClip(ctx);
    
    CGFloat stemColors[] = {
        0.00, 0.92, 1.00, 1.0, // Top vibrant cyan
        0.00, 0.65, 0.88, 1.0  // Deep cyan
    };
    CGGradientRef stemGrad = CGGradientCreateWithColorComponents(colorSpace, stemColors, NULL, 2);
    CGContextDrawLinearGradient(ctx, stemGrad, CGPointMake(center.x, center.y + stemArmLength/2.0), CGPointMake(center.x, center.y - stemArmLength/2.0), 0);
    CGGradientRelease(stemGrad);
    
    // Stem top highlight
    CGContextRestoreGState(ctx);
    
    CGContextSaveGState(ctx);
    CGContextSetStrokeColorWithColor(ctx, [NSColor colorWithCalibratedWhite:1.0 alpha:0.65].CGColor);
    CGContextSetLineWidth(ctx, 2.0 * scale);
    CGContextAddPath(ctx, cgStem);
    CGContextStrokePath(ctx);
    CGContextRestoreGState(ctx);
    
    CGColorSpaceRelease(colorSpace);
}

void drawMenubarIcon(CGContextRef ctx, CGFloat size) {
    // Coordinate space (0,0) to (size,size) - monochrome template icon
    CGFloat scale = size / 36.0;
    
    CGContextSetStrokeColorWithColor(ctx, [NSColor blackColor].CGColor);
    CGContextSetFillColorWithColor(ctx, [NSColor blackColor].CGColor);
    
    // Keycap outer profile (tapered perspective)
    CGFloat pad = 3.0 * scale;
    CGFloat w = size - pad * 2.0;
    CGFloat h = size - pad * 2.0;
    
    CGRect outerRect = CGRectMake(pad, pad, w, h);
    NSBezierPath *outer = [NSBezierPath bezierPathWithRoundedRect:outerRect xRadius:5.0 * scale yRadius:5.0 * scale];
    outer.lineWidth = 2.4 * scale;
    [outer stroke];
    
    // Inner keycap top face
    CGRect innerRect = CGRectMake(pad + 4.5 * scale, pad + 4.5 * scale, w - 9.0 * scale, h - 9.0 * scale);
    NSBezierPath *inner = [NSBezierPath bezierPathWithRoundedRect:innerRect xRadius:2.5 * scale yRadius:2.5 * scale];
    inner.lineWidth = 1.6 * scale;
    [inner stroke];
    
    // Center tactile cross dot
    CGFloat crossArm = 2.2 * scale;
    CGFloat crossLen = 6.0 * scale;
    CGFloat cx = size / 2.0;
    CGFloat cy = size / 2.0;
    
    CGRect ch = CGRectMake(cx - crossLen/2.0, cy - crossArm/2.0, crossLen, crossArm);
    CGRect cv = CGRectMake(cx - crossArm/2.0, cy - crossLen/2.0, crossArm, crossLen);
    CGContextFillRect(ctx, ch);
    CGContextFillRect(ctx, cv);
}

BOOL saveBitmapToPNG(NSBitmapImageRep *rep, NSString *path) {
    NSData *data = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    return [data writeToFile:path atomically:YES];
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSLog(@"==> Generating Clackity App Icons and Menubar Icons...");
        
        NSString *iconsetPath = @"Resources/AppIcon.iconset";
        [[NSFileManager defaultManager] createDirectoryAtPath:iconsetPath withIntermediateDirectories:YES attributes:nil error:nil];
        
        NSArray *sizes = @[
            @{@"name": @"icon_16x16.png", @"size": @(16)},
            @{@"name": @"icon_16x16@2x.png", @"size": @(32)},
            @{@"name": @"icon_32x32.png", @"size": @(32)},
            @{@"name": @"icon_32x32@2x.png", @"size": @(64)},
            @{@"name": @"icon_128x128.png", @"size": @(128)},
            @{@"name": @"icon_128x128@2x.png", @"size": @(256)},
            @{@"name": @"icon_256x256.png", @"size": @(256)},
            @{@"name": @"icon_256x256@2x.png", @"size": @(512)},
            @{@"name": @"icon_512x512.png", @"size": @(512)},
            @{@"name": @"icon_512x512@2x.png", @"size": @(1024)}
        ];
        
        for (NSDictionary *dict in sizes) {
            NSInteger sz = [dict[@"size"] integerValue];
            NSString *filename = dict[@"name"];
            NSString *filePath = [iconsetPath stringByAppendingPathComponent:filename];
            
            NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                           pixelsWide:sz
                                                                           pixelsHigh:sz
                                                                        bitsPerSample:8
                                                                      samplesPerPixel:4
                                                                             hasAlpha:YES
                                                                             isPlanar:NO
                                                                       colorSpaceName:NSDeviceRGBColorSpace
                                                                          bytesPerRow:0
                                                                         bitsPerPixel:32];
            
            NSGraphicsContext *nsCtx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
            [NSGraphicsContext setCurrentContext:nsCtx];
            CGContextRef ctx = (CGContextRef)[nsCtx graphicsPort];
            
            drawAppIcon(ctx, sz);
            
            saveBitmapToPNG(rep, filePath);
        }
        
        // Generate Menubar Icon (18x18 and 36x36 @2x)
        NSArray *mbSizes = @[
            @{@"name": @"Resources/MenuBarIcon.png", @"size": @(18)},
            @{@"name": @"Resources/MenuBarIcon@2x.png", @"size": @(36)}
        ];
        
        for (NSDictionary *dict in mbSizes) {
            NSInteger sz = [dict[@"size"] integerValue];
            NSString *filePath = dict[@"name"];
            
            NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                           pixelsWide:sz
                                                                           pixelsHigh:sz
                                                                        bitsPerSample:8
                                                                      samplesPerPixel:4
                                                                             hasAlpha:YES
                                                                             isPlanar:NO
                                                                       colorSpaceName:NSDeviceRGBColorSpace
                                                                          bytesPerRow:0
                                                                         bitsPerPixel:32];
            
            NSGraphicsContext *nsCtx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
            [NSGraphicsContext setCurrentContext:nsCtx];
            CGContextRef ctx = (CGContextRef)[nsCtx graphicsPort];
            
            drawMenubarIcon(ctx, sz);
            
            saveBitmapToPNG(rep, filePath);
        }
        
        NSLog(@"==> Successfully generated icon PNGs!");
    }
    return 0;
}
