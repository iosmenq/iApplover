// overlay2.m
// App Info Overlay - lightweight dylib for MobileSubstrate/LibSubstitute
// Compile with the provided Makefile.

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <spawn.h>
#import <ifaddrs.h>
#import <arpa/inet.h>
#import <sys/sysctl.h>
#import <objc/runtime.h>

extern char **environ;

static UIWindow *gWindow = nil;

#pragma mark - Helpers

static NSString *uptimeString(void) {
    struct timespec boottime;
    size_t size = sizeof(boottime);
    int mib[2] = {CTL_KERN, KERN_BOOTTIME};
    if (sysctl(mib, 2, &boottime, &size, NULL, 0) != -1 && boottime.tv_sec != 0) {
        time_t bsec = boottime.tv_sec;
        time_t now = time(NULL);
        time_t diff = now - bsec;
        int days = diff / 86400;
        int hours = (diff % 86400) / 3600;
        int mins = (diff % 3600) / 60;
        return [NSString stringWithFormat:@"%dd %dh %dm", days, hours, mins];
    }
    return @"(unknown)";
}

static NSString *deviceModel(void) {
    size_t size = 0;
    sysctlbyname("hw.machine", NULL, &size, NULL, 0);
    if (size) {
        char *machine = malloc(size);
        sysctlbyname("hw.machine", machine, &size, NULL, 0);
        NSString *m = [NSString stringWithUTF8String:machine];
        free(machine);
        return m ?: @"(unknown)";
    }
    return @"(unknown)";
}

static NSString *currentBundleIdentifier(void) {
    NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
    return bid ?: @"(no bundle id)";
}

static pid_t currentPid(void) {
    return getpid();
}

#pragma mark - Actions

static void doCopyBundleID(NSString *bundleID) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIPasteboard *pb = [UIPasteboard generalPasteboard];
        pb.string = bundleID;
    });
}

static void doDumpInfo(NSString *bundleID) {
    NSMutableString *s = [NSMutableString string];
    [s appendFormat:@"Timestamp: %@\n", [NSDate date]];
    [s appendFormat:@"BundleID: %@\n", bundleID];
    [s appendFormat:@"PID: %d\n", currentPid()];
    [s appendFormat:@"Device Model: %@\n", deviceModel()];
    [s appendFormat:@"iOS Version: %@\n", [[UIDevice currentDevice] systemVersion]];
    [s appendFormat:@"Uptime: %@\n", uptimeString()];

    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    [fmt setDateFormat:@"yyyyMMdd_HHmmss"];
    NSString *fn = [NSString stringWithFormat:@"/var/mobile/Documents/app_info_%@.txt",
                    [fmt stringFromDate:[NSDate date]]];

    NSError *err = nil;
    BOOL ok = [s writeToFile:fn atomically:YES encoding:NSUTF8StringEncoding error:&err];
    if (!ok) {
        NSLog(@"[AppInfoOverlay] failed to write dump: %@", err);
    } else {
        NSLog(@"[AppInfoOverlay] dumped info to %@", fn);
    }
}

static void doRespringIfPossible(void) {
    pid_t pid;
    char *argv[] = {"killall", "-9", "SpringBoard", NULL};
    int st = posix_spawnp(&pid, "killall", NULL, NULL, argv, environ);
    if (st != 0) {
        char *argv2[] = {"launchctl", "reboot", "userspace", NULL};
        posix_spawnp(&pid, "launchctl", NULL, NULL, argv2, environ);
    }
}

#pragma mark - UI

static UIButton *makeButton(NSString *title) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.translatesAutoresizingMaskIntoConstraints = NO;
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    b.layer.cornerRadius = 8;
    b.layer.borderWidth = 1.0;
    b.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.9].CGColor;
    b.contentEdgeInsets = UIEdgeInsetsMake(8, 12, 8, 12);
    b.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.6];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    return b;
}

static void presentOverlay(void) {
    if (gWindow) return;
    CGRect b = [UIScreen mainScreen].bounds;
    gWindow = [[UIWindow alloc] initWithFrame:CGRectMake(10, 60, b.size.width - 20, 160)];
    gWindow.windowLevel = UIWindowLevelStatusBar + 2000;
    gWindow.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.75];
    gWindow.layer.cornerRadius = 12;
    gWindow.clipsToBounds = YES;
    gWindow.hidden = NO;

    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = [UIColor clearColor];
    gWindow.rootViewController = vc;

    NSString *bundleID = currentBundleIdentifier();
    pid_t pid = currentPid();
    NSString *model = deviceModel();
    NSString *iosv = [[UIDevice currentDevice] systemVersion];
    NSString *upt = uptimeString();

    UILabel *lbl = [[UILabel alloc] init];
    lbl.translatesAutoresizingMaskIntoConstraints = NO;
    lbl.numberOfLines = 0;
    lbl.textColor = [UIColor whiteColor];
    lbl.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular];
    lbl.text = [NSString stringWithFormat:@"Bundle: %@\nPID: %d\nModel: %@\niOS: %@\nUptime: %@",
                bundleID, pid, model, iosv, upt];

    [vc.view addSubview:lbl];

    UIButton *copyBtn = makeButton(@"Copy Bundle ID");
    UIButton *dumpBtn = makeButton(@"Dump Info");
    UIButton *closeBtn = makeButton(@"Close");
    UIButton *respringBtn = makeButton(@"Respring");

    [vc.view addSubview:copyBtn];
    [vc.view addSubview:dumpBtn];
    [vc.view addSubview:closeBtn];
    [vc.view addSubview:respringBtn];

    // constraints
    [NSLayoutConstraint activateConstraints:@[
        [lbl.leadingAnchor constraintEqualToAnchor:vc.view.leadingAnchor constant:12],
        [lbl.topAnchor constraintEqualToAnchor:vc.view.topAnchor constant:12],
        [lbl.trailingAnchor constraintEqualToAnchor:vc.view.trailingAnchor constant:-12],

        [copyBtn.leadingAnchor constraintEqualToAnchor:vc.view.leadingAnchor constant:12],
        [copyBtn.topAnchor constraintEqualToAnchor:lbl.bottomAnchor constant:8],

        [dumpBtn.leadingAnchor constraintEqualToAnchor:copyBtn.trailingAnchor constant:8],
        [dumpBtn.centerYAnchor constraintEqualToAnchor:copyBtn.centerYAnchor],

        [respringBtn.leadingAnchor constraintEqualToAnchor:dumpBtn.trailingAnchor constant:8],
        [respringBtn.centerYAnchor constraintEqualToAnchor:dumpBtn.centerYAnchor],

        [closeBtn.trailingAnchor constraintEqualToAnchor:vc.view.trailingAnchor constant:-12],
        [closeBtn.centerYAnchor constraintEqualToAnchor:copyBtn.centerYAnchor]
    ]];

    // actions
    [copyBtn addTarget:[NSBlockOperation blockOperationWithBlock:^{
        doCopyBundleID(bundleID);
    }] action:@selector(main) forControlEvents:UIControlEventTouchUpInside];

    [dumpBtn addTarget:[NSBlockOperation blockOperationWithBlock:^{
        doDumpInfo(bundleID);
    }] action:@selector(main) forControlEvents:UIControlEventTouchUpInside];

    [respringBtn addTarget:[NSBlockOperation blockOperationWithBlock:^{
        doRespringIfPossible();
    }] action:@selector(main) forControlEvents:UIControlEventTouchUpInside];

    [closeBtn addTarget:[NSBlockOperation blockOperationWithBlock:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            gWindow.hidden = YES;
            gWindow = nil; // weakW kullanılmadı, hata da kalktı
        });
    }] action:@selector(main) forControlEvents:UIControlEventTouchUpInside];
}

__attribute__((constructor))
static void init_overlay2(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        @try {
            presentOverlay();
        } @catch (NSException *ex) {
            NSLog(@"[AppInfoOverlay] present failed: %@", ex);
        }
    });
}
