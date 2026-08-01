#import <ScreenSaver/ScreenSaver.h>
#import <CoreLocation/CoreLocation.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreImage/CoreImage.h>
#import <AppKit/AppKit.h>

// Match index.html RADIUS_KM / MIN_ALT_M — keep in sync when either changes.
static const double kOFRadiusKm = 40.0;
static const double kOFMinAltM = 500.0;
static const NSTimeInterval kOFPollSeconds = 90.0;
// Fallback if Core Location never answers (common: .saver never appears in Location Services).
// Wembley Park — author location; still fine as generic NW London ADS-B coverage.
static const double kOFDefaultLat = 51.5578;
static const double kOFDefaultLon = -0.2795;

static void OFLog(NSString *msg) {
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], msg];
    NSArray<NSString *> *paths = @[
        [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/OverheadFlights.log"],
        [@"/tmp" stringByAppendingPathComponent:@"OverheadFlights.log"],
    ];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    for (NSString *path in paths) {
        @try {
            [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:nil];
            if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
                [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
                continue;
            }
            NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
            if (!fh) { continue; }
            [fh seekToEndOfFile];
            [fh writeData:data];
            [fh closeFile];
        } @catch (__unused NSException *ex) {
        }
    }
    NSLog(@"[OverheadFlights] %@", msg);
}

// Demo props from 21st Etheral Shadow:
// color="rgba(128,128,128,1)" animation={{scale:100,speed:90}} noise={{opacity:1,scale:1.2}} sizing="fill"
static const CGFloat kOFAnimScale = 100.0;
static const CGFloat kOFAnimSpeed = 90.0;
static const CGFloat kOFNoiseOpacity = 1.0; // original uses opacity/2 for the layer
static const CGFloat kOFNoiseScale = 1.2;

static CGFloat OFMapRange(CGFloat v, CGFloat inMin, CGFloat inMax, CGFloat outMin, CGFloat outMax) {
    if (inMax == inMin) return outMin;
    CGFloat t = (v - inMin) / (inMax - inMin);
    if (t < 0) t = 0;
    if (t > 1) t = 1;
    return outMin + t * (outMax - outMin);
}

/// Faithful native port of Etheral Shadow (Jatin Yadav / 21st.dev).
/// Same assets + same prop mapping; Core Image instead of SVG filter (WKWebView broken in screensaver).
@interface OFEtherealBGView : NSView
@property (nonatomic, strong) NSTimer *animTimer;
@property (nonatomic, assign) CFTimeInterval t0;
@property (nonatomic, assign) BOOL reduceMotion;
@property (nonatomic, strong) CIContext *ciContext;
@property (nonatomic, strong) CIImage *maskImage;
@property (nonatomic, strong) NSImage *noiseImage;
@property (nonatomic, assign) BOOL assetsLoaded;
@property (nonatomic, assign) BOOL assetsFailed;
@end

@implementation OFEtherealBGView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.backgroundColor = NSColor.blackColor.CGColor;
        self.t0 = CACurrentMediaTime();
        self.ciContext = [CIContext contextWithOptions:@{
            kCIContextUseSoftwareRenderer: @NO,
            kCIContextWorkingColorSpace: [NSNull null],
        }];
        if (@available(macOS 10.12, *)) {
            self.reduceMotion = NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
        }
    }
    return self;
}

- (BOOL)isOpaque { return YES; }

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (self.window) {
        [self loadAssetsIfNeeded];
        [self startAnimating];
    } else {
        [self stopAnimating];
    }
}

- (void)startAnimating {
    if (self.animTimer) {
        [self setNeedsDisplay:YES];
        return;
    }
    __weak typeof(self) weakSelf = self;
    // ~24fps — displacement reads as continuous
    self.animTimer = [NSTimer timerWithTimeInterval:1.0 / 24.0 repeats:YES block:^(__unused NSTimer *t) {
        [weakSelf setNeedsDisplay:YES];
    }];
    [[NSRunLoop mainRunLoop] addTimer:self.animTimer forMode:NSRunLoopCommonModes];
    [self setNeedsDisplay:YES];
}

- (void)stopAnimating {
    [self.animTimer invalidate];
    self.animTimer = nil;
}

- (void)dealloc {
    [self stopAnimating];
}

- (void)loadAssetsIfNeeded {
    if (self.assetsLoaded || self.assetsFailed) return;

    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSURL *maskURL = [bundle URLForResource:@"etheral-mask" withExtension:@"png" subdirectory:@"Web"];
    if (!maskURL) maskURL = [bundle URLForResource:@"etheral-mask" withExtension:@"png"];
    NSURL *noiseURL = [bundle URLForResource:@"etheral-noise" withExtension:@"png" subdirectory:@"Web"];
    if (!noiseURL) noiseURL = [bundle URLForResource:@"etheral-noise" withExtension:@"png"];

    if (!maskURL) {
        // Fallback: try absolute path next to binary resources
        OFLog(@"etheral-mask.png missing in bundle");
        self.assetsFailed = YES;
        return;
    }

    CIImage *mask = [CIImage imageWithContentsOfURL:maskURL];
    if (!mask) {
        OFLog(@"etheral-mask failed to load CIImage");
        self.assetsFailed = YES;
        return;
    }
    self.maskImage = mask;

    if (noiseURL) {
        self.noiseImage = [[NSImage alloc] initWithContentsOfURL:noiseURL];
    }
    self.assetsLoaded = YES;
    OFLog(@"etheral assets loaded (mask+noise)");
}

/// Cover-fit transform: scale mask to fill target size, centered.
- (CIImage *)of_maskCoveringSize:(CGSize)size {
    CIImage *mask = self.maskImage;
    if (!mask) return nil;
    CGRect me = mask.extent;
    if (me.size.width < 1 || me.size.height < 1) return nil;

    CGFloat sx = size.width / me.size.width;
    CGFloat sy = size.height / me.size.height;
    CGFloat s = MAX(sx, sy); // sizing="fill" → cover
    CGAffineTransform t = CGAffineTransformMakeScale(s, s);
    CIImage *scaled = [mask imageByApplyingTransform:t];
    CGRect se = scaled.extent;
    CGFloat dx = (size.width - se.size.width) * 0.5 - se.origin.x;
    CGFloat dy = (size.height - se.size.height) * 0.5 - se.origin.y;
    scaled = [scaled imageByApplyingTransform:CGAffineTransformMakeTranslation(dx, dy)];
    return [scaled imageByCroppingToRect:CGRectMake(0, 0, size.width, size.height)];
}

- (void)drawRect:(NSRect)dirtyRect {
    NSRect b = self.bounds;
    [[NSColor blackColor] setFill];
    NSRectFill(b);

    CGFloat w = b.size.width;
    CGFloat h = b.size.height;
    if (w < 2 || h < 2) return;

    [self loadAssetsIfNeeded];
    if (!self.assetsLoaded || !self.maskImage || !self.ciContext) {
        // Last-resort soft blob so something always shows
        NSGradient *g = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithWhite:0.5 alpha:0.35]
                                                      endingColor:[NSColor colorWithWhite:0.5 alpha:0]];
        NSPoint c = NSMakePoint(w * 0.5, h * 0.5);
        [g drawFromCenter:c radius:0 toCenter:c radius:MIN(w, h) * 0.45 options:0];
        return;
    }

    // --- Same prop mapping as original Component (mapRange / Si) ---
    // animation.scale 100 → displacement N = 100, inset expansion 100
    CGFloat N = OFMapRange(kOFAnimScale, 1, 100, 20, 100);
    // animation.speed 90 → hue cycle duration (seconds) = map(...)/25
    CGFloat cycleSec = OFMapRange(kOFAnimSpeed, 1, 100, 1000, 50) / 25.0; // ~5.84s
    CFTimeInterval elapsed = self.reduceMotion ? 0 : (CACurrentMediaTime() - self.t0);
    CGFloat phase = self.reduceMotion ? 0 : (elapsed / cycleSec); // revolutions

    // Render at 1x view points (Retina: use backing scale)
    CGFloat scale = self.window.backingScaleFactor > 0 ? self.window.backingScaleFactor : 2.0;
    if (scale < 1) scale = 1;
    // Cap work for big displays
    if (scale > 1.5) scale = 1.5;
    CGSize px = CGSizeMake(floor(w * scale), floor(h * scale));
    CGRect extent = CGRectMake(0, 0, px.width, px.height);
    CGFloat nPx = N * scale;

    // 1) Solid color rgba(128,128,128,1) — same as demo
    CIColor *gray = [CIColor colorWithRed:128.0 / 255.0 green:128.0 / 255.0 blue:128.0 / 255.0 alpha:1];
    CIImage *colorImg = [[[CIImage imageWithColor:gray] imageByCroppingToRect:extent]
                         imageByClampingToExtent];

    // 2) Mask image, sizing fill (cover), centered — original mask PNG
    CIImage *mask = [self of_maskCoveringSize:px];
    if (!mask) return;

    // Use mask luminance as alpha over gray (soft cloud shape)
    // CISourceIn: shows colorImg only where mask is opaque
    CIFilter *sourceIn = [CIFilter filterWithName:@"CISourceInCompositing"];
    [sourceIn setValue:colorImg forKey:kCIInputImageKey];
    [sourceIn setValue:mask forKey:kCIInputBackgroundImageKey];
    CIImage *shaped = sourceIn.outputImage;
    if (!shaped) shaped = colorImg;

    // Expand bounds like original inset:-N for displacement bleed
    CGRect expanded = CGRectInset(extent, -nPx, -nPx);

    // 3) Displacement field (stand-in for feTurbulence + hueRotate + matrix + displacementMap)
    //    Animate by scrolling random noise (hueRotate loop in original ≈ continuous field change)
    CIFilter *rand = [CIFilter filterWithName:@"CIRandomGenerator"];
    CIImage *field = rand.outputImage;
    CGFloat scrollX = phase * px.width * 0.85;
    CGFloat scrollY = phase * px.height * 0.55;
    field = [field imageByApplyingTransform:CGAffineTransformMakeTranslation(scrollX, scrollY)];
    field = [field imageByCroppingToRect:expanded];

    // Soften field so warp is cloudy not sparkly (like low baseFrequency turbulence)
    CIFilter *fieldBlur = [CIFilter filterWithName:@"CIGaussianBlur"];
    [fieldBlur setValue:field forKey:kCIInputImageKey];
    [fieldBlur setValue:@(12.0 * scale) forKey:kCIInputRadiusKey];
    CIImage *softField = fieldBlur.outputImage ?: field;

    // Dual displacement ≈ two feDisplacementMap passes (circulation + undulation)
    CIFilter *disp1 = [CIFilter filterWithName:@"CIDisplacementDistortion"];
    [disp1 setValue:shaped forKey:kCIInputImageKey];
    [disp1 setValue:softField forKey:@"inputDisplacementImage"];
    [disp1 setValue:@(nPx) forKey:kCIInputScaleKey];
    CIImage *dist1 = disp1.outputImage ?: shaped;

    // Second pass with offset field
    CIImage *field2 = [softField imageByApplyingTransform:CGAffineTransformMakeTranslation(97, 53)];
    CIFilter *disp2 = [CIFilter filterWithName:@"CIDisplacementDistortion"];
    [disp2 setValue:dist1 forKey:kCIInputImageKey];
    [disp2 setValue:field2 forKey:@"inputDisplacementImage"];
    [disp2 setValue:@(nPx * 0.65) forKey:kCIInputScaleKey];
    CIImage *dist2 = disp2.outputImage ?: dist1;

    // Original also applies CSS blur(4px) on the filtered layer
    CIFilter *softBlur = [CIFilter filterWithName:@"CIGaussianBlur"];
    [softBlur setValue:dist2 forKey:kCIInputImageKey];
    [softBlur setValue:@(4.0 * scale) forKey:kCIInputRadiusKey];
    CIImage *finalCI = softBlur.outputImage ?: dist2;
    finalCI = [finalCI imageByCroppingToRect:extent];

    CGImageRef cgImg = [self.ciContext createCGImage:finalCI fromRect:extent];
    if (cgImg) {
        CGContextRef cg = [[NSGraphicsContext currentContext] CGContext];
        CGContextSaveGState(cg);
        // Flip for CI → AppKit
        CGContextTranslateCTM(cg, 0, h);
        CGContextScaleCTM(cg, 1, -1);
        CGContextDrawImage(cg, CGRectMake(0, 0, w, h), cgImg);
        CGContextRestoreGState(cg);
        CGImageRelease(cgImg);
    }

    // 4) Noise overlay: opacity = noise.opacity/2, tile size = scale*200 (CSS px)
    if (self.noiseImage && kOFNoiseOpacity > 0) {
        CGFloat tile = kOFNoiseScale * 200.0; // 240
        CGFloat opac = kOFNoiseOpacity * 0.5; // 0.5
        CGFloat ox = self.reduceMotion ? 0 : fmod(elapsed * 12.0, tile);
        CGFloat oy = self.reduceMotion ? 0 : fmod(elapsed * 9.0, tile);

        NSGraphicsContext *gc = [NSGraphicsContext currentContext];
        CGContextRef cg = gc.CGContext;
        CGContextSaveGState(cg);
        CGContextSetAlpha(cg, opac);
        CGContextSetBlendMode(cg, kCGBlendModeSoftLight);

        // Tile noise
        for (CGFloat y = -tile + oy; y < h + tile; y += tile) {
            for (CGFloat x = -tile + ox; x < w + tile; x += tile) {
                [self.noiseImage drawInRect:NSMakeRect(x, y, tile, tile)
                                   fromRect:NSZeroRect
                                  operation:NSCompositingOperationSourceOver
                                   fraction:1.0
                             respectFlipped:YES
                                      hints:nil];
            }
        }
        CGContextRestoreGState(cg);
    }
}

@end

@interface OverheadFlightsView : ScreenSaverView <CLLocationManagerDelegate>
@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, assign) CLLocationCoordinate2D lastCoordinate;
@property (nonatomic, assign) BOOL hasCoordinate;
@property (nonatomic, assign) BOOL didStart;
@property (nonatomic, strong) NSTimer *pollTimer;
@property (nonatomic, strong) NSURLSessionDataTask *inflightTask;

// Native ethereal fog (no WebView — WebKit often paints nothing in screensaver).
@property (nonatomic, strong) OFEtherealBGView *bgView;

// Full-screen live UI (AppKit — WKWebView text fails to paint inside legacyScreenSaver).
@property (nonatomic, strong) NSStackView *liveStack;
@property (nonatomic, strong) NSTextField *monogramLabel;
@property (nonatomic, strong) NSTextField *callsignLabel;
@property (nonatomic, strong) NSTextField *airlineLabel;
@property (nonatomic, strong) NSTextField *destinationLabel;
@property (nonatomic, strong) NSTextField *metaLabel;
@property (nonatomic, strong) NSLayoutConstraint *stackCenterY;
@property (nonatomic, strong) NSTimer *driftTimer;
@property (nonatomic, copy) NSString *lastShownCallsign;
@property (nonatomic, assign) NSTimeInterval driftPhase;

// Route lookup (adsbdb) — separate async call from position; best-effort, often has no data.
@property (nonatomic, strong) NSURLSessionDataTask *destTask;
@property (nonatomic, copy) NSString *destInFlightCallsign;
@property (nonatomic, strong) NSMutableDictionary<NSString *, id> *destCache;

// Settings grid only
@property (nonatomic, strong) NSStackView *placeholderStack;
@property (nonatomic, assign) CGFloat lastTypographySize;
@end

@implementation OverheadFlightsView

static double OFHaversineKm(double lat1, double lon1, double lat2, double lon2) {
    const double R = 6371.0;
    const double toRad = M_PI / 180.0;
    double dLat = (lat2 - lat1) * toRad;
    double dLon = (lon2 - lon1) * toRad;
    double a = sin(dLat / 2) * sin(dLat / 2)
        + cos(lat1 * toRad) * cos(lat2 * toRad) * sin(dLon / 2) * sin(dLon / 2);
    return R * 2.0 * atan2(sqrt(a), sqrt(1.0 - a));
}

static NSString *OFCleanCallsign(id raw) {
    if (![raw isKindOfClass:[NSString class]]) { return @""; }
    NSString *s = [(NSString *)raw stringByTrimmingCharactersInSet:
                   [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return [s uppercaseString];
}

static NSString *OFAirlineFromCallsign(NSString *cs) {
    if (cs.length < 3) { return @""; }
    static NSDictionary *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{
            @"BAW": @"British Airways", @"SHT": @"British Airways", @"CFE": @"BA CityFlyer",
            @"EZY": @"easyJet", @"EJU": @"easyJet", @"EZJ": @"easyJet",
            @"RYR": @"Ryanair", @"RUK": @"Ryanair UK",
            @"TOM": @"TUI", @"EXS": @"Jet2",
            @"VIR": @"Virgin Atlantic", @"VLG": @"Vueling",
            @"AFR": @"Air France", @"DLH": @"Lufthansa", @"KLM": @"KLM", @"KLC": @"KLM Cityhopper",
            @"UAL": @"United", @"AAL": @"American", @"DAL": @"Delta",
            @"SIA": @"Singapore Airlines", @"CPA": @"Cathay Pacific", @"ANA": @"ANA", @"JAL": @"JAL",
            @"QFA": @"Qantas", @"UAE": @"Emirates", @"ETD": @"Etihad", @"QTR": @"Qatar Airways",
            @"THY": @"Turkish Airlines", @"SAS": @"SAS", @"FIN": @"Finnair", @"IBE": @"Iberia",
            @"AUA": @"Austrian", @"SWR": @"Swiss", @"EIN": @"Aer Lingus", @"ICE": @"Icelandair",
            @"WZZ": @"Wizz Air", @"NAX": @"Norwegian",
            @"CAL": @"China Airlines", @"EVA": @"EVA Air", @"TNA": @"Mandarin Airlines",
            @"ACA": @"Air Canada", @"JBU": @"JetBlue", @"SWA": @"Southwest", @"ASA": @"Alaska",
            @"LOG": @"Loganair", @"EWG": @"Eurowings",
        };
    });
    NSString *prefix = [cs substringToIndex:3];
    return map[prefix] ?: @"";
}

static NSString *OFBearingLabel(double deg) {
    static NSArray *dirs;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dirs = @[@"North", @"Northeast", @"East", @"Southeast",
                 @"South", @"Southwest", @"West", @"Northwest"];
    });
    NSInteger i = (NSInteger)llround(deg / 45.0) % 8;
    if (i < 0) { i += 8; }
    return dirs[i];
}

static double OFBearingDeg(double lat1, double lon1, double lat2, double lon2) {
    const double toRad = M_PI / 180.0;
    double phi1 = lat1 * toRad;
    double phi2 = lat2 * toRad;
    double dLon = (lon2 - lon1) * toRad;
    double y = sin(dLon) * cos(phi2);
    double x = cos(phi1) * sin(phi2) - sin(phi1) * cos(phi2) * cos(dLon);
    double deg = atan2(y, x) * 180.0 / M_PI;
    deg = fmod(deg + 360.0, 360.0);
    return deg;
}

- (instancetype)initWithFrame:(NSRect)frame isPreview:(BOOL)isPreview {
    self = [super initWithFrame:frame isPreview:isPreview];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (void)dealloc {
    [self.pollTimer invalidate];
    [self.driftTimer invalidate];
    [self.inflightTask cancel];
    [self.destTask cancel];
}

- (void)commonInit {
    self.wantsLayer = YES;
    // Near-black with a cool night tint (DESIGN.md) — not pure #000, not pure white type later.
    self.layer.backgroundColor = [NSColor colorWithRed:0.02 green:0.02 blue:0.028 alpha:1].CGColor;
    self.animationTimeInterval = 0;
    self.lastCoordinate = CLLocationCoordinate2DMake(kOFDefaultLat, kOFDefaultLon);
    self.hasCoordinate = NO;
    self.lastTypographySize = -1;

    BOOL preview = self.isPreview;
    OFLog([NSString stringWithFormat:@"commonInit preview=%@ frame=%.0fx%.0f",
           preview ? @"YES" : @"NO", self.bounds.size.width, self.bounds.size.height]);

    if (preview) {
        [self installPreviewStub];
        return;
    }

    // Full-screen: native ethereal fog + AppKit flight type on top.
    [self installEtherealBackground];
    [self installLiveUI];
    [self startLocation];
    [self startNativePolling];
}

#pragma mark - Ethereal background (native — WebKit fails in screensaver)

- (void)installEtherealBackground {
    if (self.bgView || self.isPreview) { return; }

    OFEtherealBGView *bg = [[OFEtherealBGView alloc] initWithFrame:self.bounds];
    bg.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self addSubview:bg positioned:NSWindowBelow relativeTo:nil];
    bg.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [bg.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [bg.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [bg.topAnchor constraintEqualToAnchor:self.topAnchor],
        [bg.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];
    self.bgView = bg;
    [bg startAnimating];
    OFLog(@"ethereal bg native installed");
}

#pragma mark - Preview stub (settings grid)

- (void)installPreviewStub {
    CGFloat callsignSize = 22;
    CGFloat secondarySize = 9;
    CGFloat monoSize = 8;

    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeCenterX;
    stack.spacing = 4;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:stack];

    NSTextField *mono = [NSTextField labelWithString:@"BA"];
    mono.textColor = [NSColor colorWithWhite:0.55 alpha:1];
    mono.font = [NSFont monospacedSystemFontOfSize:monoSize weight:NSFontWeightRegular];
    mono.alignment = NSTextAlignmentCenter;

    NSTextField *callsign = [NSTextField labelWithString:@"BAW482"];
    callsign.textColor = [NSColor colorWithWhite:0.92 alpha:1];
    callsign.font = [NSFont systemFontOfSize:callsignSize weight:NSFontWeightUltraLight];
    callsign.alignment = NSTextAlignmentCenter;

    NSTextField *airline = [NSTextField labelWithString:@"British Airways"];
    airline.textColor = [NSColor colorWithWhite:0.55 alpha:1];
    airline.font = [NSFont systemFontOfSize:secondarySize weight:NSFontWeightLight];
    airline.alignment = NSTextAlignmentCenter;

    NSTextField *route = [NSTextField labelWithString:@"→ London (LHR)"];
    route.textColor = [NSColor colorWithWhite:0.42 alpha:1];
    route.font = [NSFont systemFontOfSize:secondarySize weight:NSFontWeightLight];
    route.alignment = NSTextAlignmentCenter;

    [stack addArrangedSubview:mono];
    [stack addArrangedSubview:callsign];
    [stack addArrangedSubview:airline];
    [stack addArrangedSubview:route];

    [NSLayoutConstraint activateConstraints:@[
        [stack.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor constant:-2],
        [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:8],
        [stack.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-8],
    ]];

    self.placeholderStack = stack;
}

#pragma mark - Live full-screen UI (impeccable: quiet ambient type)

// Soft silver hierarchy — DESIGN.md (not pure white on pure black).
static const CGFloat kOFWhiteMonogram    = 0.28;
static const CGFloat kOFWhiteCallsign    = 0.82;
static const CGFloat kOFWhiteAirline     = 0.48;
static const CGFloat kOFWhiteDestination = 0.36;
static const CGFloat kOFWhiteMeta        = 0.34;

- (NSTextField *)of_emptyLabel {
    NSTextField *t = [NSTextField labelWithString:@""];
    t.alignment = NSTextAlignmentCenter;
    t.maximumNumberOfLines = 2;
    t.lineBreakMode = NSLineBreakByTruncatingTail;
    t.drawsBackground = NO;
    t.bezeled = NO;
    t.editable = NO;
    t.selectable = NO;
    t.wantsLayer = YES;
    return t;
}

- (void)of_applyText:(NSString *)text
             toLabel:(NSTextField *)label
                size:(CGFloat)size
              weight:(NSFontWeight)weight
               white:(CGFloat)white
                kern:(CGFloat)kernEm
                mono:(BOOL)mono
          monoDigits:(BOOL)monoDigits {
    if (text.length == 0) {
        label.stringValue = @"";
        return;
    }
    NSFont *font;
    if (monoDigits) {
        font = [NSFont monospacedDigitSystemFontOfSize:size weight:weight];
    } else if (mono) {
        font = [NSFont monospacedSystemFontOfSize:size weight:weight];
    } else {
        font = [NSFont systemFontOfSize:size weight:weight];
    }
    NSDictionary *attrs = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: [NSColor colorWithWhite:white alpha:1],
        NSKernAttributeName: @(kernEm * size),
    };
    label.attributedStringValue =
        [[NSAttributedString alloc] initWithString:text attributes:attrs];
}

/// Screen-relative callsign size (DESIGN.md ~10% height). No fixed pt caps.
- (CGFloat)of_callsignPointSize {
    NSSize s = self.bounds.size;
    CGFloat h = s.height > 1 ? s.height : 900;
    CGFloat w = s.width > 1 ? s.width : 1400;
    CGFloat byHeight = h * 0.10;
    CGFloat byWidth = (w * 0.86) / 7.0;
    return MIN(byHeight, byWidth);
}

- (BOOL)of_reduceMotion {
    if (@available(macOS 10.12, *)) {
        return NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion;
    }
    return NO;
}

- (void)updateTypographyForBounds {
    if (!self.callsignLabel) { return; }

    CGFloat callsignSize = [self of_callsignPointSize];
    if (fabs(callsignSize - self.lastTypographySize) < 0.25) {
        // Still refresh optical center offset if height changed without size jump.
        if (self.stackCenterY) {
            self.stackCenterY.constant = self.bounds.size.height * 0.06;
        }
        return;
    }
    self.lastTypographySize = callsignSize;

    // Hierarchy ratios (DESIGN.md): monogram whisper, callsign hero, quiet secondaries.
    CGFloat monoSize = callsignSize * 0.20;
    CGFloat airlineSize = callsignSize * 0.30;
    CGFloat destinationSize = callsignSize * 0.26;
    CGFloat metaSize = callsignSize * 0.24;

    // Re-apply current strings with new metrics if any text is showing.
    NSString *mono = self.monogramLabel.stringValue;
    NSString *cs = self.callsignLabel.stringValue;
    NSString *air = self.airlineLabel.stringValue;
    NSString *dest = self.destinationLabel.stringValue;
    NSString *meta = self.metaLabel.stringValue;

    // If using attributed strings, stringValue may still work.
    if (self.monogramLabel.attributedStringValue.length) {
        mono = self.monogramLabel.attributedStringValue.string;
    }
    if (self.callsignLabel.attributedStringValue.length) {
        cs = self.callsignLabel.attributedStringValue.string;
    }
    if (self.airlineLabel.attributedStringValue.length) {
        air = self.airlineLabel.attributedStringValue.string;
    }
    if (self.destinationLabel.attributedStringValue.length) {
        dest = self.destinationLabel.attributedStringValue.string;
    }
    if (self.metaLabel.attributedStringValue.length) {
        meta = self.metaLabel.attributedStringValue.string;
    }

    if (cs.length > 0) {
        [self of_applyText:mono toLabel:self.monogramLabel size:monoSize
                    weight:NSFontWeightRegular white:kOFWhiteMonogram kern:0.28 mono:YES monoDigits:NO];
        [self of_applyText:cs toLabel:self.callsignLabel size:callsignSize
                    weight:NSFontWeightUltraLight white:kOFWhiteCallsign kern:0.08 mono:NO monoDigits:YES];
        [self of_applyText:air toLabel:self.airlineLabel size:airlineSize
                    weight:NSFontWeightLight white:kOFWhiteAirline kern:0.06 mono:NO monoDigits:NO];
        [self of_applyText:dest toLabel:self.destinationLabel size:destinationSize
                    weight:NSFontWeightLight white:kOFWhiteDestination kern:0.06 mono:NO monoDigits:NO];
        [self of_applyText:meta toLabel:self.metaLabel size:metaSize
                    weight:NSFontWeightLight white:kOFWhiteMeta kern:0.10 mono:NO monoDigits:NO];
    }

    // Asymmetric rhythm: tight mono→callsign, airy callsign→airline.
    self.liveStack.spacing = 0;
    [self.liveStack setCustomSpacing:callsignSize * 0.06 afterView:self.monogramLabel];
    [self.liveStack setCustomSpacing:callsignSize * 0.16 afterView:self.callsignLabel];
    [self.liveStack setCustomSpacing:callsignSize * 0.10 afterView:self.airlineLabel];
    [self.liveStack setCustomSpacing:callsignSize * 0.10 afterView:self.destinationLabel];

    if (self.stackCenterY) {
        // Sit below geometric center so lock-screen clock keeps the upper third.
        self.stackCenterY.constant = self.bounds.size.height * 0.06;
    }

    OFLog([NSString stringWithFormat:@"typography callsign=%.1fpt bounds=%.0fx%.0f",
           callsignSize, self.bounds.size.width, self.bounds.size.height]);
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    if (!self.isPreview && self.liveStack) {
        [self updateTypographyForBounds];
    }
}

- (void)layout {
    [super layout];
    if (!self.isPreview && self.liveStack) {
        [self updateTypographyForBounds];
    }
}

- (void)installLiveUI {
    if (self.liveStack) { return; }

    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeCenterX;
    stack.spacing = 0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.wantsLayer = YES;
    stack.alphaValue = 0;
    // Always above ethereal fog
    if (self.bgView) {
        [self addSubview:stack positioned:NSWindowAbove relativeTo:self.bgView];
    } else {
        [self addSubview:stack];
    }

    self.monogramLabel = [self of_emptyLabel];
    self.callsignLabel = [self of_emptyLabel];
    self.airlineLabel = [self of_emptyLabel];
    self.destinationLabel = [self of_emptyLabel];
    self.metaLabel = [self of_emptyLabel];

    [stack addArrangedSubview:self.monogramLabel];
    [stack addArrangedSubview:self.callsignLabel];
    [stack addArrangedSubview:self.airlineLabel];
    [stack addArrangedSubview:self.destinationLabel];
    [stack addArrangedSubview:self.metaLabel];

    CGFloat sidePad = MAX(20, self.bounds.size.width * 0.06);
    self.stackCenterY = [stack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor
                                                            constant:self.bounds.size.height * 0.06];

    [NSLayoutConstraint activateConstraints:@[
        [stack.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        self.stackCenterY,
        [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:sidePad],
        [stack.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-sidePad],
        [stack.widthAnchor constraintLessThanOrEqualToAnchor:self.widthAnchor multiplier:0.88],
    ]];

    self.liveStack = stack;
    self.lastTypographySize = -1;
    [self updateTypographyForBounds];
    [self showEmpty];
    [self startDriftIfNeeded];
    OFLog(@"installLiveUI ok (impeccable ambient)");
}

- (void)startDriftIfNeeded {
    if (self.isPreview || [self of_reduceMotion]) { return; }
    if (self.driftTimer) { return; }

    self.driftPhase = 0;
    __weak typeof(self) weakSelf = self;
    // ~4 min full cycle, tiny amplitude — anti-burn-in, not decoration.
    self.driftTimer = [NSTimer timerWithTimeInterval:2.0 repeats:YES block:^(__unused NSTimer *t) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || !self.stackCenterY || self.callsignLabel.hidden) { return; }
        self.driftPhase += 2.0;
        CGFloat amp = MAX(3.0, self.bounds.size.height * 0.004);
        CGFloat base = self.bounds.size.height * 0.06;
        CGFloat y = base + sin(self.driftPhase / 240.0 * M_PI * 2.0) * amp;
        self.stackCenterY.constant = y;
    }];
    [[NSRunLoop mainRunLoop] addTimer:self.driftTimer forMode:NSRunLoopCommonModes];
}

- (void)showEmpty {
    self.lastShownCallsign = nil;
    [self.destTask cancel];
    self.destTask = nil;
    self.destInFlightCallsign = nil;
    self.monogramLabel.stringValue = @"";
    self.callsignLabel.stringValue = @"";
    self.airlineLabel.stringValue = @"";
    self.destinationLabel.stringValue = @"";
    self.metaLabel.stringValue = @"";
    self.monogramLabel.hidden = YES;
    self.callsignLabel.hidden = YES;
    self.airlineLabel.hidden = YES;
    self.destinationLabel.hidden = YES;
    self.metaLabel.hidden = YES;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
        ctx.duration = [self of_reduceMotion] ? 0 : 0.45;
        ctx.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        self.liveStack.animator.alphaValue = 0;
    }];
}

- (void)showFlightCallsign:(NSString *)callsign
                   airline:(NSString *)airline
                      altM:(double)altM
                   bearing:(NSString *)bearing {
    NSString *cs = OFCleanCallsign(callsign);
    if (cs.length == 0) {
        [self showEmpty];
        return;
    }

    NSString *mono = cs.length >= 2 ? [cs substringToIndex:MIN(3, (NSUInteger)cs.length)] : cs;
    NSString *air = airline.length ? airline : OFAirlineFromCallsign(cs);

    NSInteger altMRound = (NSInteger)llround(altM);
    NSInteger altFt = (NSInteger)llround(altM / 0.3048);
    // Thin separators — quieter than dense spacing.
    NSString *meta = [NSString stringWithFormat:@"%ld m  ·  %ld ft", (long)altMRound, (long)altFt];
    if (bearing.length > 0) {
        meta = [meta stringByAppendingFormat:@"  ·  %@", bearing];
    }

    BOOL isNew = ![cs isEqualToString:self.lastShownCallsign ?: @""];
    self.lastShownCallsign = cs;

    if (isNew) {
        // New flight — any in-flight route lookup was for the previous plane; drop it.
        [self.destTask cancel];
        self.destTask = nil;
        self.destInFlightCallsign = nil;
        self.destinationLabel.stringValue = @"";
        self.destinationLabel.hidden = YES;
    }

    self.lastTypographySize = -1; // force type reflow
    [self updateTypographyForBounds];

    CGFloat callsignSize = [self of_callsignPointSize];
    [self of_applyText:mono toLabel:self.monogramLabel size:callsignSize * 0.20
                weight:NSFontWeightRegular white:kOFWhiteMonogram kern:0.28 mono:YES monoDigits:NO];
    [self of_applyText:cs toLabel:self.callsignLabel size:callsignSize
                weight:NSFontWeightUltraLight white:kOFWhiteCallsign kern:0.08 mono:NO monoDigits:YES];
    [self of_applyText:air toLabel:self.airlineLabel size:callsignSize * 0.30
                weight:NSFontWeightLight white:kOFWhiteAirline kern:0.06 mono:NO monoDigits:NO];
    [self of_applyText:meta toLabel:self.metaLabel size:callsignSize * 0.24
                weight:NSFontWeightLight white:kOFWhiteMeta kern:0.10 mono:NO monoDigits:NO];

    self.monogramLabel.hidden = (mono.length == 0);
    self.callsignLabel.hidden = NO;
    self.airlineLabel.hidden = (air.length == 0);
    self.metaLabel.hidden = NO;

    [self fetchDestinationForCallsign:cs];

    if (isNew) {
        self.liveStack.alphaValue = 0;
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
            ctx.duration = [self of_reduceMotion] ? 0 : 0.4;
            ctx.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0.22 :1 :0.36 :1];
            self.liveStack.animator.alphaValue = 1;
        }];
    } else {
        self.liveStack.alphaValue = 1;
    }

    OFLog([NSString stringWithFormat:@"UI show %@", cs]);
}

#pragma mark - Route / destination lookup (adsbdb — separate from position, often has no data)

- (NSMutableDictionary<NSString *, id> *)destCache {
    if (!_destCache) {
        _destCache = [NSMutableDictionary dictionary];
    }
    return _destCache;
}

static NSString *OFRouteLabel(NSDictionary *place) {
    if (![place isKindOfClass:[NSDictionary class]]) { return @""; }
    NSString *city = [place[@"municipality"] isKindOfClass:[NSString class]] ? place[@"municipality"] : @"";
    NSString *iata = [place[@"iata_code"] isKindOfClass:[NSString class]] ? place[@"iata_code"] : @"";
    NSString *name = [place[@"name"] isKindOfClass:[NSString class]] ? place[@"name"] : @"";
    if (city.length && iata.length) { return [NSString stringWithFormat:@"%@ (%@)", city, iata]; }
    if (city.length) { return city; }
    if (iata.length) { return iata; }
    if (name.length) { return name; }
    return @"";
}

// Session-cached, keyed by callsign. Cache also stores an empty route for a lookup with no
// data, so we don't refetch a private/GA/military flight that adsbdb simply has nothing for.
- (void)fetchDestinationForCallsign:(NSString *)cs {
    if (cs.length == 0) { return; }

    NSDictionary *cached = self.destCache[cs];
    if (cached) {
        if ([cs isEqualToString:self.lastShownCallsign]) {
            [self applyRouteResult:cached];
        }
        return;
    }

    if ([self.destInFlightCallsign isEqualToString:cs]) { return; }
    self.destInFlightCallsign = cs;

    NSString *encoded = [cs stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet] ?: cs;
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://api.adsbdb.com/v0/callsign/%@", encoded]];
    if (!url) {
        self.destInFlightCallsign = nil;
        return;
    }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.timeoutInterval = 15;
    [req setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [req setValue:@"OverheadFlights-macOS/1.0" forHTTPHeaderField:@"User-Agent"];

    [self.destTask cancel];

    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }

        dispatch_async(dispatch_get_main_queue(), ^{
            if ([self.destInFlightCallsign isEqualToString:cs]) {
                self.destInFlightCallsign = nil;
            }

            NSString *routeText = @"";
            NSString *iata = @"";
            NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
            if (!error && data.length > 0 && http.statusCode >= 200 && http.statusCode < 300) {
                id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                NSDictionary *route = nil;
                if ([root isKindOfClass:[NSDictionary class]]) {
                    id resp = root[@"response"];
                    if ([resp isKindOfClass:[NSDictionary class]]) {
                        route = resp[@"flightroute"];
                    }
                }
                if ([route isKindOfClass:[NSDictionary class]]) {
                    NSString *origin = OFRouteLabel(route[@"origin"]);
                    NSString *dest = OFRouteLabel(route[@"destination"]);
                    if (origin.length && dest.length) {
                        routeText = [NSString stringWithFormat:@"%@ → %@", origin, dest];
                    } else {
                        routeText = dest.length ? dest : origin;
                    }

                    NSDictionary *airline = route[@"airline"];
                    if ([airline isKindOfClass:[NSDictionary class]] &&
                        [airline[@"iata"] isKindOfClass:[NSString class]]) {
                        iata = (NSString *)airline[@"iata"];
                    }
                }
            }

            NSDictionary *result = @{ @"route": routeText, @"iata": iata };
            self.destCache[cs] = result;

            // Guard against the plane having already left / changed by the time this resolves.
            if ([cs isEqualToString:self.lastShownCallsign]) {
                [self applyRouteResult:result];
            }
        });
    }];
    self.destTask = task;
    [task resume];
}

- (void)applyRouteResult:(NSDictionary *)result {
    NSString *routeText = [result[@"route"] isKindOfClass:[NSString class]] ? result[@"route"] : @"";
    NSString *iata = [result[@"iata"] isKindOfClass:[NSString class]] ? result[@"iata"] : @"";
    if (routeText.length > 0) {
        [self applyDestinationText:routeText];
    }
    // IATA is a nicer monogram than the raw callsign prefix already showing — swap it in when known.
    if (iata.length > 0) {
        [self applyMonogramText:iata];
    }
}

- (void)applyDestinationText:(NSString *)text {
    if (!self.destinationLabel || text.length == 0) { return; }
    CGFloat callsignSize = [self of_callsignPointSize];
    [self of_applyText:text toLabel:self.destinationLabel size:callsignSize * 0.26
                weight:NSFontWeightLight white:kOFWhiteDestination kern:0.06 mono:NO monoDigits:NO];
    self.destinationLabel.hidden = NO;
}

- (void)applyMonogramText:(NSString *)text {
    if (!self.monogramLabel || text.length == 0) { return; }
    CGFloat callsignSize = [self of_callsignPointSize];
    [self of_applyText:text.uppercaseString toLabel:self.monogramLabel size:callsignSize * 0.20
                weight:NSFontWeightRegular white:kOFWhiteMonogram kern:0.28 mono:YES monoDigits:NO];
    self.monogramLabel.hidden = NO;
}

- (void)startAnimation {
    [super startAnimation];
    if (self.didStart) { return; }
    self.didStart = YES;

    OFLog([NSString stringWithFormat:@"startAnimation preview=%@", self.isPreview ? @"YES" : @"NO"]);

    if (self.isPreview) {
        return;
    }

    if (!self.bgView) {
        [self installEtherealBackground];
    } else {
        [self.bgView startAnimating];
    }
    if (!self.liveStack) {
        [self installLiveUI];
    } else {
        [self addSubview:self.liveStack positioned:NSWindowAbove relativeTo:self.bgView];
    }
    [self startLocation];
    [self startNativePolling];
}

- (void)stopAnimation {
    [super stopAnimation];
    [self.pollTimer invalidate];
    self.pollTimer = nil;
    [self.driftTimer invalidate];
    self.driftTimer = nil;
    [self.bgView stopAnimating];
    [self.inflightTask cancel];
    self.inflightTask = nil;
    [self.destTask cancel];
    self.destTask = nil;
    self.destInFlightCallsign = nil;
}

- (void)animateOneFrame {
}

- (BOOL)hasConfigureSheet { return NO; }
- (NSWindow *)configureSheet { return nil; }

#pragma mark - Native flight poll

- (void)startNativePolling {
    if (self.isPreview) { return; }
    if (self.pollTimer) {
        [self fetchAndShowFlights];
        return;
    }

    OFLog(@"startNativePolling");
    __weak typeof(self) weakSelf = self;
    self.pollTimer = [NSTimer timerWithTimeInterval:kOFPollSeconds repeats:YES block:^(__unused NSTimer *t) {
        [weakSelf fetchAndShowFlights];
    }];
    [[NSRunLoop mainRunLoop] addTimer:self.pollTimer forMode:NSRunLoopCommonModes];
    [self fetchAndShowFlights];
}

- (CLLocationCoordinate2D)queryCoordinate {
    if (self.hasCoordinate) {
        return self.lastCoordinate;
    }
    return CLLocationCoordinate2DMake(kOFDefaultLat, kOFDefaultLon);
}

- (void)fetchAndShowFlights {
    if (self.isPreview) { return; }
    if (self.inflightTask && self.inflightTask.state == NSURLSessionTaskStateRunning) {
        OFLog(@"fetch skip — already in flight");
        return;
    }

    CLLocationCoordinate2D c = [self queryCoordinate];
    double nm = kOFRadiusKm / 1.852;
    NSString *urlStr = [NSString stringWithFormat:
        @"https://api.airplanes.live/v2/point/%.5f/%.5f/%.2f",
        c.latitude, c.longitude, nm];
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) {
        OFLog(@"bad url");
        return;
    }

    [self.inflightTask cancel];

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.timeoutInterval = 20;
    [req setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [req setValue:@"OverheadFlights-macOS/1.0" forHTTPHeaderField:@"User-Agent"];

    OFLog([NSString stringWithFormat:@"fetch %@", urlStr]);

    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task =
        [[NSURLSession sharedSession] dataTaskWithRequest:req
                                        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) { return; }

        if (error) {
            OFLog([NSString stringWithFormat:@"fetch err %@", error.localizedDescription]);
            return;
        }
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
        if (http.statusCode < 200 || http.statusCode >= 300 || data.length == 0) {
            OFLog([NSString stringWithFormat:@"fetch http %ld", (long)http.statusCode]);
            return;
        }

        NSError *jsonErr = nil;
        id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
        if (![root isKindOfClass:[NSDictionary class]]) {
            OFLog([NSString stringWithFormat:@"json err %@", jsonErr.localizedDescription]);
            return;
        }
        NSArray *acList = root[@"ac"];
        if (![acList isKindOfClass:[NSArray class]]) {
            acList = @[];
        }

        NSDictionary *nearest = [self nearestAircraftFrom:acList around:c];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!nearest) {
                OFLog([NSString stringWithFormat:@"UI empty total=%ld", (long)acList.count]);
                [self showEmpty];
                return;
            }
            NSString *cs = OFCleanCallsign(nearest[@"flight"]);
            if (cs.length == 0) {
                cs = OFCleanCallsign(nearest[@"hex"]);
            }
            double altM = [nearest[@"alt_m"] doubleValue];
            double lat = [nearest[@"lat"] doubleValue];
            double lon = [nearest[@"lon"] doubleValue];
            CLLocationCoordinate2D origin = [self queryCoordinate];
            double brg = OFBearingDeg(origin.latitude, origin.longitude, lat, lon);
            NSString *bearing = OFBearingLabel(brg);
            NSString *airline = OFAirlineFromCallsign(cs);

            OFLog([NSString stringWithFormat:@"nearest=%@ total=%ld dist=%.1fkm",
                   cs, (long)acList.count, [nearest[@"dist_km"] doubleValue]]);
            [self showFlightCallsign:cs airline:airline altM:altM bearing:bearing];
        });
    }];
    self.inflightTask = task;
    [task resume];
}

- (nullable NSDictionary *)nearestAircraftFrom:(NSArray *)acList around:(CLLocationCoordinate2D)c {
    NSDictionary *best = nil;
    double bestDist = DBL_MAX;

    for (id item in acList) {
        if (![item isKindOfClass:[NSDictionary class]]) { continue; }
        NSDictionary *ac = (NSDictionary *)item;

        NSNumber *latN = ac[@"lat"];
        NSNumber *lonN = ac[@"lon"];
        if (![latN isKindOfClass:[NSNumber class]] || ![lonN isKindOfClass:[NSNumber class]]) {
            continue;
        }
        double lat = latN.doubleValue;
        double lon = lonN.doubleValue;

        id altRaw = ac[@"alt_baro"];
        if (altRaw == nil || altRaw == [NSNull null]) { continue; }
        if ([altRaw isKindOfClass:[NSString class]] &&
            [((NSString *)altRaw) caseInsensitiveCompare:@"ground"] == NSOrderedSame) {
            continue;
        }
        double altFt = 0;
        if ([altRaw isKindOfClass:[NSNumber class]]) {
            altFt = [(NSNumber *)altRaw doubleValue];
        } else if ([altRaw isKindOfClass:[NSString class]]) {
            altFt = [(NSString *)altRaw doubleValue];
        } else {
            continue;
        }
        double altM = altFt * 0.3048;
        if (altM < kOFMinAltM) { continue; }

        double dist = OFHaversineKm(c.latitude, c.longitude, lat, lon);
        if (dist > kOFRadiusKm) { continue; }
        if (dist < bestDist) {
            bestDist = dist;
            best = @{
                @"flight": ac[@"flight"] ?: [NSNull null],
                @"hex": ac[@"hex"] ?: [NSNull null],
                @"lat": @(lat),
                @"lon": @(lon),
                @"alt_baro": @(altFt),
                @"alt_m": @(altM),
                @"dist_km": @(dist),
            };
        }
    }
    return best;
}

#pragma mark - Location

- (void)startLocation {
    CLLocationManager *m = [CLLocationManager new];
    m.delegate = self;
    m.desiredAccuracy = kCLLocationAccuracyKilometer;
    self.locationManager = m;

    CLAuthorizationStatus status;
    if (@available(macOS 11.0, *)) {
        status = m.authorizationStatus;
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        status = [CLLocationManager authorizationStatus];
#pragma clang diagnostic pop
    }
    OFLog([NSString stringWithFormat:@"location status=%d", (int)status]);

    if (status == kCLAuthorizationStatusNotDetermined) {
        [m requestWhenInUseAuthorization];
    }
    [m requestLocation];
}

- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager {
    CLAuthorizationStatus status;
    if (@available(macOS 11.0, *)) {
        status = manager.authorizationStatus;
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        status = [CLLocationManager authorizationStatus];
#pragma clang diagnostic pop
    }
    OFLog([NSString stringWithFormat:@"location auth changed=%d", (int)status]);
    if (status == kCLAuthorizationStatusAuthorizedAlways ||
        status == kCLAuthorizationStatusAuthorized) {
        [manager requestLocation];
    }
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    CLLocation *loc = locations.lastObject;
    if (!loc) { return; }
    self.lastCoordinate = loc.coordinate;
    self.hasCoordinate = YES;
    OFLog([NSString stringWithFormat:@"location ok %.4f,%.4f",
           loc.coordinate.latitude, loc.coordinate.longitude]);
    [self fetchAndShowFlights];
    [manager stopUpdatingLocation];
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    OFLog([NSString stringWithFormat:@"location fail %@ — using Wembley default",
           error.localizedDescription]);
    [self fetchAndShowFlights];
}

@end
