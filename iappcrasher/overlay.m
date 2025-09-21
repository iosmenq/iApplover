// overlay.m
// Compile: see Makefile below
#import <objc/runtime.h>
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <spawn.h>
#import <ifaddrs.h>
#import <arpa/inet.h>

extern char **environ;

static UIWindow *overlayWindow = nil;

#pragma mark - Utilities

// Return array of local IPv4 addresses as strings
NSArray<NSString *> *localIPAddresses(void) {
    NSMutableArray *ips = [NSMutableArray array];
    struct ifaddrs *ifaddr = NULL;
    if (getifaddrs(&ifaddr) == -1) return ips;
    for (struct ifaddrs *ifa = ifaddr; ifa != NULL; ifa = ifa->ifa_next) {
        if (!ifa->ifa_addr) continue;
        if (ifa->ifa_addr->sa_family == AF_INET) {
            char addrBuf[INET_ADDRSTRLEN];
            struct sockaddr_in *sa = (struct sockaddr_in *)ifa->ifa_addr;
            if (inet_ntop(AF_INET, &sa->sin_addr, addrBuf, sizeof(addrBuf))) {
                NSString *name = [NSString stringWithUTF8String:ifa->ifa_name];
                NSString *ip = [NSString stringWithUTF8String:addrBuf];
                [ips addObject:[NSString stringWithFormat:@"%@: %@", name, ip]];
            }
        }
    }
    freeifaddrs(ifaddr);
    return ips;
}

// Synchronously fetch public IP (simple)
NSString *publicIPSync(NSTimeInterval timeout) {
    __block NSString *result = @"(unknown)";
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    NSURL *url = [NSURL URLWithString:@"https://api.ipify.org?format=text"];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.timeoutInterval = timeout;
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
                                                                 completionHandler:^(NSData *data, NSURLResponse *resp, NSError *error){
        if (data && !error) {
            NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if (s.length) result = s;
        } else {
            result = [NSString stringWithFormat:@"(err: %@)", error.localizedDescription];
        }
        dispatch_semaphore_signal(sem);
    }];
    [task resume];
    dispatch_time_t to = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC));
    if (dispatch_semaphore_wait(sem, to) != 0) {
        result = @"(timeout)";
    }
    return result;
}

#pragma mark - Actions

static void doCrash(void) {
    // Crash intentionally
    abort();
}

static void doRespring(void) {
    pid_t pid;
    char *argv[] = {"killall", "-9", "SpringBoard", NULL};
    int st = posix_spawnp(&pid, "killall", NULL, NULL, argv, environ);
    if (st != 0) {
        // fallback: try launchctl reboot userspace
        char *argv2[] = {"launchctl", "reboot", "userspace", NULL};
        posix_spawnp(&pid, "launchctl", NULL, NULL, argv2, environ);
    }
}

#pragma mark - UI

static UIButton *makeButton(NSString *title, SEL sel, id target) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.translatesAutoresizingMaskIntoConstraints = NO;
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    b.layer.cornerRadius = 10;
    b.layer.borderWidth = 1.0;
    b.layer.borderColor = [UIColor whiteColor].CGColor;
    b.contentEdgeInsets = UIEdgeInsetsMake(10, 20, 10, 20);
    [b addTarget:target action:sel forControlEvents:UIControlEventTouchUpInside];
    return b;
}

static void presentOverlay(void) {
    if (overlayWindow) return; // already shown
    CGRect bounds = [UIScreen mainScreen].bounds;
    overlayWindow = [[UIWindow alloc] initWithFrame:bounds];
    overlayWindow.windowLevel = UIWindowLevelStatusBar + 2000; // topmost
    overlayWindow.backgroundColor = [UIColor blackColor];
    overlayWindow.hidden = NO;

    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = [UIColor blackColor];
    overlayWindow.rootViewController = vc;

    // initial blank (fully black). After 0.5s we'll populate text/buttons.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        // gather info
        NSArray *local = localIPAddresses();
        NSString *localStr = local.count ? [local componentsJoinedByString:@"\n"] : @"(no local IP)";
        NSString *pub = publicIPSync(3.0);
        NSString *sftpPort = @"22";

        // labels
        UILabel *infoLabel = [[UILabel alloc] init];
        infoLabel.translatesAutoresizingMaskIntoConstraints = NO;
        infoLabel.numberOfLines = 0;
        infoLabel.textAlignment = NSTextAlignmentCenter;
        infoLabel.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
        infoLabel.textColor = [UIColor whiteColor];
        infoLabel.text = [NSString stringWithFormat:@"Local IPs:\n%@\n\nPublic IP:\n%@\n\nSFTP Port:\n%@", localStr, pub, sftpPort];

        [vc.view addSubview:infoLabel];

        UIButton *crashBtn = makeButton(@"Crash", @selector(_crashTapped:), vc);
        UIButton *respringBtn = makeButton(@"Respring", @selector(_respringTapped:), vc);

        [vc.view addSubview:crashBtn];
        [vc.view addSubview:respringBtn];

        // wire actions using blocks by adding targets to vc which will call C functions
        // We'll add simple selectors on vc that call the C funcs via objc_setAssociatedObject / category
        // Simpler: add target to call functions via blocks using UIControlEventTouchUpInside with action method below.

        // constraints
        [NSLayoutConstraint activateConstraints:@[
            [infoLabel.centerXAnchor constraintEqualToAnchor:vc.view.centerXAnchor],
            [infoLabel.centerYAnchor constraintEqualToAnchor:vc.view.centerYAnchor constant:-80],
            [infoLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:vc.view.leadingAnchor constant:20],
            [infoLabel.trailingAnchor constraintLessThanOrEqualToAnchor:vc.view.trailingAnchor constant:-20],

            [respringBtn.centerXAnchor constraintEqualToAnchor:vc.view.centerXAnchor],
            [respringBtn.topAnchor constraintEqualToAnchor:infoLabel.bottomAnchor constant:20],

            [crashBtn.centerXAnchor constraintEqualToAnchor:vc.view.centerXAnchor],
            [crashBtn.topAnchor constraintEqualToAnchor:respringBtn.bottomAnchor constant:12]
        ]];

        // add action targets - use block wrappers by creating selectors on vc via category would be cleaner.
        // We'll use objc_setAssociatedObject to attach blocks and a generic invoker.

        // store blocks
        void (^crashBlock)(void) = ^{
            doCrash();
        };
        void (^respringBlock)(void) = ^{
            doRespring();
        };

        // attach to buttons via objc runtime wrapper
        // create temporary target object
        id targetObj = [NSObject new];
        // crash
        [crashBtn addTarget:targetObj action:@selector(_invokeCrash:) forControlEvents:UIControlEventTouchUpInside];
        [respringBtn addTarget:targetObj action:@selector(_invokeRespring:) forControlEvents:UIControlEventTouchUpInside];

        // store blocks in associated objects
        objc_setAssociatedObject(targetObj, "crashBlockKey", crashBlock, OBJC_ASSOCIATION_COPY);
        objc_setAssociatedObject(targetObj, "respringBlockKey", respringBlock, OBJC_ASSOCIATION_COPY);

        // add methods to targetObj class dynamically if needed (we rely on category methods below to handle selectors)
    });
}

// We need to add selector implementations used above via category on NSObject.
#import <objc/runtime.h>

@interface NSObject (OverlayActions)
- (void)_invokeCrash:(id)sender;
- (void)_invokeRespring:(id)sender;
@end

@implementation NSObject (OverlayActions)
- (void)_invokeCrash:(id)sender {
    void (^b)(void) = objc_getAssociatedObject(self, "crashBlockKey");
    if (b) b();
}
- (void)_invokeRespring:(id)sender {
    void (^b)(void) = objc_getAssociatedObject(self, "respringBlockKey");
    if (b) b();
}
@end

#pragma mark - Constructor / entrypoint

__attribute__((constructor))
static void init_overlay(void) {
    // Delay a little to let host app finish launching UI
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @try {
            presentOverlay();
        } @catch (NSException *ex) {
            NSLog(@"Overlay present failed: %@", ex);
        }
    });
}
