#import <substrate.h>
#import <CoreGraphics/CoreGraphics.h>

@interface SpringBoard
- (UIInterfaceOrientation)activeInterfaceOrientation;
@end

@interface SBReachabilitySettings : NSObject
@property(nonatomic) double reachabilityInteractiveKeepAlive;
@property(nonatomic) double reachabilityDefaultKeepAlive;
@property CGFloat yOffsetFactor;
@end

@interface SBRootSettings
- (SBReachabilitySettings *)reachabilitySettings;
@end

@interface SBPrototypeController
+ (SBPrototypeController *)sharedInstance;
- (SBRootSettings *)rootSettings;
@end

@interface UIScreen (Addition)
- (CGFloat)_interfaceOrientation;
- (CGRect)_interfaceOrientedBounds;
- (CGRect)applicationFrame;
@end

NSString *const forceOrientationKey = @"SBPSForceReachOrientation";
NSString *const syncOrientationKey = @"SBPSReachabilityGoodOrientation";
NSString *const defaultTimeKey = @"SBPSForceReachDefaultKeepAlive";
NSString *const interactiveTimeKey = @"SBPSForceReachInteractiveKeepAlive";
NSString *const insaneKey = @"SBPSForceReachInsane";
NSString *const instantKey = @"SBPSInstantReachability";

BOOL overrideOrientation = NO;
BOOL currentlyOverrideDistance = NO;
BOOL instantOverride = NO;
BOOL noDeactivate = NO;

static BOOL boolValueForKey(NSString *key, BOOL defaultValue)
{
	Boolean valid = NO;
	Boolean value = CFPreferencesGetAppBooleanValue((CFStringRef)key, CFSTR("com.apple.springboard"), &valid);
	return valid ? value : defaultValue;
}

static BOOL myInsane(BOOL defaultValue)
{
	BOOL insane = boolValueForKey(insaneKey, NO);
	return insane ? YES : defaultValue;
}

static double myKeepAliveTime(NSString *key, double defaultValue)
{
	BOOL unlimited = boolValueForKey(key, NO);
	return unlimited ? MAXFLOAT : defaultValue;
}

%group SpringBoard

%hook SBReachabilitySettings

- (double)reachabilityDefaultKeepAlive
{
	return myKeepAliveTime(defaultTimeKey, %orig);
}

- (double)reachabilityInteractiveKeepAlive
{
	return myKeepAliveTime(interactiveTimeKey, %orig);
}

%end

%hook SBReachabilityManager

- (void)_handleReachabilityActivated
{
	overrideOrientation = boolValueForKey(forceOrientationKey, NO);
	%orig;
	overrideOrientation = NO;
}

- (void)deactivateReachabilityModeForObserver:(id)arg1
{
	if (noDeactivate)
		return;
	%orig;
}

%end

%hook SBNotificationCenterViewController

- (void)viewDidDisappear:(id)arg1
{
	noDeactivate = boolValueForKey(instantKey, NO);
	%orig;
	noDeactivate = NO;
}

%end

%hook SBUIController

- (void)_showNotificationsGestureBeganWithLocation:(id)arg1
{
	noDeactivate = boolValueForKey(instantKey, NO);
	%orig;
	noDeactivate = NO;
}

%end

%hook SpringBoard

- (void)_deactivateReachability
{
	if (instantOverride)
		return;
	%orig;
}

- (UIInterfaceOrientation)activeInterfaceOrientation
{
	return overrideOrientation && !currentlyOverrideDistance ? UIInterfaceOrientationPortrait : %orig;
}

%end

%hook SBIconController

- (BOOL)_shouldRespondToReachability
{
	return myInsane(%orig);
}

%end

%hook SBAppSwitcherController

- (BOOL)_shouldRespondToReachability
{
	return myInsane(%orig);
}

%end

%hook SBNotificationCenterController

BOOL ncOverride = NO;

- (BOOL)isTransitioning
{
	return ncOverride ? NO : %orig;
}

- (void)handleReachabilityModeActivated
{
	ncOverride = boolValueForKey(insaneKey, NO);
	%orig;
	ncOverride = NO;
}

- (void)handleReachabilityModeDeactivated
{
	ncOverride = boolValueForKey(insaneKey, NO);
	%orig;
	ncOverride = NO;
}

- (void)_cleanupAfterTransition:(id)arg1
{
	noDeactivate = boolValueForKey(instantKey, NO);
	%orig;
	noDeactivate = NO;
}

%end

%hook SBSearchViewController

BOOL svOverride = NO;

- (BOOL)_hasResults
{
	return svOverride ? YES : %orig;
}

- (void)handleReachabilityModeActivated
{
	svOverride = boolValueForKey(insaneKey, NO);
	%orig;
	svOverride = NO;
}

- (void)handleReachabilityModeDeactivated
{
	svOverride = boolValueForKey(insaneKey, NO);
	%orig;
	svOverride = NO;
}

%end

/*%hook SBFolderView

- (void)repositionForReachabilityActivated:(BOOL)activated animated:(BOOL)animated actions:(id)actions completion:(id)completion
{
	%orig;
}

%end*/

BOOL hookTranslate = NO;

%hook SBRootFolderView

- (void)_handleReachabilityActivatedAnimate:(BOOL)animate completion:(id)completion
{
	hookTranslate = boolValueForKey(forceOrientationKey, NO);
	%orig;
	hookTranslate = NO;
}

%end

/*%hook SBFloatyFolderView

- (void)_handleReachabilityActivatedAnimate:(BOOL)animated completion:(id)completion
{
	hookTranslate2 = YES;
	%orig;
	hookTranslate2 = NO;
}

%end*/

MSHook(CGAffineTransform, CGAffineTransformMakeTranslation, CGFloat tx, CGFloat ty)
{
	if (hookTranslate) {
		BOOL sync = boolValueForKey(syncOrientationKey, NO);
		currentlyOverrideDistance = YES;
		UIInterfaceOrientation orientation = [(SpringBoard *)[UIApplication sharedApplication] activeInterfaceOrientation];
		currentlyOverrideDistance = NO;
		CGFloat totalDistance = [[UIScreen mainScreen] _interfaceOrientedBounds].size.height;
		if (sync) {
			BOOL isLandscape = orientation == UIInterfaceOrientationLandscapeLeft || orientation == UIInterfaceOrientationLandscapeRight;
			if (isLandscape)
				totalDistance = [[UIScreen mainScreen] _interfaceOrientedBounds].size.width;
		}
		CGFloat yOffsetFactor = [[[%c(SBPrototypeController) sharedInstance] rootSettings] reachabilitySettings].yOffsetFactor;
		CGFloat statusBarHeight = [UIScreen mainScreen].bounds.size.height - [[UIScreen mainScreen] applicationFrame].size.height;
		CGFloat trueDistance = totalDistance*yOffsetFactor - statusBarHeight;
		if (sync) {
			switch (orientation) {
				case UIInterfaceOrientationLandscapeLeft:
					return _CGAffineTransformMakeTranslation(-trueDistance, 0);
				case UIInterfaceOrientationLandscapeRight:
					return _CGAffineTransformMakeTranslation(trueDistance, 0);
			}
		}
		return _CGAffineTransformMakeTranslation(tx, trueDistance);
	}
	return _CGAffineTransformMakeTranslation(tx, ty);
}

%end

%group UIKit

%hook UIApplication

- (void)_deactivateReachability
{
	if (instantOverride)
		return;
	%orig;
}

%end

%hook UIViewController

- (void)_presentViewController:(id)viewController withAnimationController:(id)animationController completion:(id)completion
{
	instantOverride = boolValueForKey(instantKey, NO);
	%orig;
	instantOverride = NO;
}

- (void)dismissViewControllerWithTransition:(id)transition completion:(id)completion
{
	instantOverride = boolValueForKey(instantKey, NO);
	%orig;
	instantOverride = NO;
}

%end

%hook UINavigationController

- (void)pushViewController:(id)viewController transition:(id)transition forceImmediate:(BOOL)immediate
{
	instantOverride = boolValueForKey(instantKey, NO);
	%orig;
	instantOverride = NO;
}

- (id)_popViewControllerWithTransition:(id)transition allowPoppingLast:(BOOL)last
{
	instantOverride = boolValueForKey(instantKey, NO);
	id r = %orig;
	instantOverride = NO;
	return r;
}

- (void)_popViewControllerAndUpdateInterfaceOrientationAnimated:(BOOL)animated
{
	instantOverride = boolValueForKey(instantKey, NO);
	%orig;
	instantOverride = NO;
}

%end

%hook UIInputWindowController 

- (void)moveFromPlacement:(id)arg1 toPlacement:(id)arg2 starting:(id)arg3 completion:(id)arg4
{
	instantOverride = boolValueForKey(instantKey, NO);
	%orig;
	instantOverride = NO;
}

%end

%end

BOOL shouldInjectUIKit()
{
	BOOL inject = NO;
	NSArray *args = [[NSClassFromString(@"NSProcessInfo") processInfo] arguments];
	NSUInteger count = [args count];
	if (count != 0) {
		NSString *executablePath = [args objectAtIndex:0];
		if (executablePath) {
			NSString *processName = [executablePath lastPathComponent];
			BOOL isApplication = [executablePath rangeOfString:@"/Application"].location != NSNotFound;
			BOOL isSpringBoard = [processName isEqualToString:@"SpringBoard"];
			return isApplication || isSpringBoard;
		}
	}
	return inject;
}

%ctor
{
	BOOL isSpringBoard = [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.springboard"];
	if (isSpringBoard) {
		MSHookFunction(CGAffineTransformMakeTranslation, MSHake(CGAffineTransformMakeTranslation));
		%init(SpringBoard);
	}
	if (shouldInjectUIKit()) {
		%init(UIKit);
	}
}
