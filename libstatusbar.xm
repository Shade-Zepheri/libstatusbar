#import <substrate.h>
#import "common.h"
#import "UIStatusBarCustomItem.h"
#import "UIStatusBarCustomItemView.h"
#import "LSStatusBarServer.h"
#import "LSStatusBarClient.h"
#import "LSStatusBarItem.h"

NSMutableArray* customItems[3];	 // left, right, center

#pragma mark UIStatusBar* Hooks

%hook UIStatusBarItem
+ (id)itemWithType:(int)arg1 {
	id ret = %orig;
	if (ret == nil) {
		ret = [(UIStatusBarCustomItem*)[%c(UIStatusBarCustomItem) alloc] initWithType:arg1];
	}
	return ret;
}

+ (id)itemWithType:(int)arg1 idiom:(int)arg2 {
	id ret = %orig;
	if (ret == nil) {
		ret = [(UIStatusBarCustomItem*)[%c(UIStatusBarCustomItem) alloc] initWithType:arg1];
	}
	return ret;
}
%end

UIStatusBarItemView* InitializeView(UIStatusBarLayoutManager *self, id item) {
	UIStatusBarItemView *_view = [item viewForManager:self];
	if (_view) {
		return _view;
	}

	UIStatusBarForegroundView *_foregroundView = MSHookIvar<UIStatusBarForegroundView*>(self, "_foregroundView");

	UIStatusBarForegroundStyleAttributes *foregroundStyle = [_foregroundView foregroundStyle];

	_view = [%c(UIStatusBarItemView) createViewForItem:item withData:nil actions:0 foregroundStyle:foregroundStyle];

	[_view setLayoutManager:self];

	int _region = MSHookIvar<int>(self, "_region");
	switch (_region) {
		case 0: {
			[_view setContentMode:UIViewContentModeLeft];
			[_view setAutoresizingMask:UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleRightMargin];
			break;
		}
		case 1: {
			[_view setContentMode:UIViewContentModeRight];
			[_view setAutoresizingMask:UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleLeftMargin];
			break;
		}
		case 2: {
			[_view setContentMode:UIViewContentModeLeft];
			[_view setAutoresizingMask:UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleLeftMargin]; // 0x25
			break;
		}
	}

	[item setView:_view forManager:self];
	return _view;
}

%hook UIStatusBarForegroundView
- (id)_computeVisibleItemsPreservingHistory:(BOOL)arg1 {
	id ret = %orig;

	__strong UIStatusBarLayoutManager* (&layoutManagers)[3](MSHookIvar<UIStatusBarLayoutManager*[3]>(self, "_layoutManagers"));

	float boundsWidth = [self bounds].size.width;
	NSMutableArray *center = [ret objectForKey:@(2)];
	CGFloat centerWidth = [layoutManagers[2] sizeNeededForItems:center];

	float edgeWidth = (boundsWidth - centerWidth) * 0.5f;

	for (int i = 0; i <= 2; i++) {
		NSMutableArray *arr = [ret objectForKey:@(i)];

		[layoutManagers[i] clearOverlapFromItems:arr];

		CGFloat arrWidth = [layoutManagers[i] sizeNeededForItems:arr];

		for (UIStatusBarCustomItem *item in customItems[i]) {
			NSNumber *visible = [[item properties] objectForKey:@"visible"];
			if (!visible || [visible boolValue]) {
				float itemWidth = [layoutManagers[i] sizeNeededForItem:item];
				if (arrWidth + itemWidth < edgeWidth + 4) {
					[arr addObject:item];
					arrWidth += itemWidth;
				} else {
					// LEET HAX to not arbitrarily cut off items??
					[arr addObject:item];
					arrWidth += itemWidth;
					//item.visible = NO;
					// TODO
				}
			}
		}

		if (arrWidth > edgeWidth - 1) {
			[layoutManagers[i] distributeOverlap:arrWidth - edgeWidth + 1 amongItems:arr];
		}
	}
	return ret;
}
%end

%hook UIStatusBarLayoutManager
- (id)_viewForItem:(id)arg1 {
	if ([arg1 isKindOfClass:[%c(UIStatusBarCustomItem) class]]) {
		return InitializeView(self, arg1);
	}
	return %orig;
}

- (id)_itemViews {
	NSMutableArray *_itemViews = %orig;

	if (_itemViews) {
		int _region = MSHookIvar<int>(self, "_region");
		if (_region < 3 && customItems[_region]) {
			for (UIStatusBarCustomItem *item in customItems[_region]) {
				UIStatusBarItemView *_view = InitializeView(self, item);
				if (_view) {
					[_itemViews addObject:_view];
				}
			}
		}
	}

	return _itemViews;
}
%end

void PrepareEnabledItemsCommon(UIStatusBarLayoutManager *self) {
	UIStatusBarForegroundView *_foregroundView = MSHookIvar<UIStatusBarForegroundView*>(self, "_foregroundView");

	float startPosition = [self _startPosition];
	for (UIStatusBarItemView *view in [self _itemViewsSortedForLayout]) {
		if (view.superview == nil) {
			view.visible = YES;
			view.frame = [self _frameForItemView:view startPosition:startPosition firstView:YES];
			[_foregroundView addSubview:view];
		}

		int type = [(UIStatusBarItem *)[view item] type];
		if (type) {
			startPosition = [self _positionAfterPlacingItemView:view startPosition:startPosition firstView:YES];
		}
	}
}

%hook UIStatusBarLayoutManager
- (BOOL)prepareEnabledItems:(BOOL*)arg1 withData:(id)arg2 actions:(int)arg3 {
	BOOL ret = %orig;
	if (!ret) {
		PrepareEnabledItemsCommon(self);
	}
	return YES;
}

- (CGFloat)_startPosition {
	CGFloat orig = %orig;
	int region = MSHookIvar<int>(self, "_region");
	NSArray *itemViews = [self _itemViewsSortedForLayout];
	if (region == 2 && [itemViews count] > 1) {
		CGFloat width = 0;
		//width -= [itemViews[0] frame].size.width;
		for (UIStatusBarItemView *view in itemViews) {
			width += view.frame.size.width;
		}
		return orig - floor(width / 2) + UIScreen.mainScreen.scale; // ... how does that even fix it?
	}
	return orig;
}

- (CGRect)rectForItems:(id)arg1 {
	int region = MSHookIvar<int>(self, "_region");

	for (UIStatusBarCustomItem *item in customItems[region]) {
		id visible = item.properties[@"visible"];
		if (!visible || [visible boolValue]) {
			[arg1 addObject:item];
		}
	}

	//return %orig;
	CGRect rect = %orig;
	if (region == 2 && [[self _itemViewsSortedForLayout] count] > 1) {
		rect.origin.x -= [self _startPosition];
	}
	return rect;
	/*CGRect rect = %orig(arg1);
	if (region == 2)
	{
		if ([[self _itemViewsSortedForLayout] count] > 1)
		{
			CGFloat width = rect.size.width;
			rect.origin.x -= floor(width / 2);
		}
	}
	return rect;*/
}
%end

%hook UIApplication
+ (void)_startWindowServerIfNecessary {
	%orig;

	static BOOL hasAlreadyRan = NO;
	if (hasAlreadyRan) {
		HBLogDebug(@"[libstatusbar] Warning: UIApplication _startWindowServerIfNecessary called more than once!");
		return;
	}
	hasAlreadyRan = YES;

	// use this only for starting client
	// register as client - make sure SpringBoard is running
	// UIKit should still not exist.../yet/
	int (*SBSSpringBoardServerPort)() = (int (*)())dlsym(RTLD_DEFAULT, "SBSSpringBoardServerPort");
	if (%c(SpringBoard) || SBSSpringBoardServerPort()) {
		[[LSStatusBarClient sharedInstance] updateStatusBar];
	}
}

- (void)applicationDidResume {
	%orig;

	int (*SBSSpringBoardServerPort)() = (int (*)())dlsym(RTLD_DEFAULT, "SBSSpringBoardServerPort");
	if (%c(SpringBoard) || SBSSpringBoardServerPort()) {
		[[LSStatusBarClient sharedInstance] updateStatusBar];
	}
}

- (void)workspace:(id)arg1 didLaunchWithCompletion:(id)arg2 {
	%orig;

	int (*SBSSpringBoardServerPort)() = (int (*)())dlsym(RTLD_DEFAULT, "SBSSpringBoardServerPort");
	if (%c(SpringBoard) || SBSSpringBoardServerPort()) {
		[[LSStatusBarClient sharedInstance] updateStatusBar];
	}
}

%new - (void)addStatusBarImageNamed:(NSString*)name removeOnExit:(BOOL)remove {
	[[LSStatusBarClient sharedInstance] setProperties:@(1) forItem:name];
}

%new - (void)addStatusBarImageNamed:(NSString*)name {
	[[LSStatusBarClient sharedInstance] setProperties:@(1) forItem:name];
}

%new - (void)removeStatusBarImageNamed:(NSString*)name {
	[[LSStatusBarClient sharedInstance] setProperties:nil forItem:name];
}
%end

%ctor {
	// we only hook UIKit apps - used as a guard band
	// TODO: may be irrelevant because of the MobileSubstrate filter for UIKit
	if (%c(UIStatusBarItem)) {
		if (%c(SpringBoard)) {
			// Initialize server
			[LSStatusBarServer sharedInstance];
		}
	} else if (!%c(UIApplication)) {
		HBLogDebug(@"[libstatusbar] not loading into this UIKit process - no UIApplication");
	} else {
		HBLogDebug(@"[libstatusbar] loaded into UIKit process without UIStatusBarItem");
	}
}
