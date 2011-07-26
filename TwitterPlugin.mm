#import <Foundation/Foundation.h>
#import <Common/LocalizedListController.h>
#import <substrate.h>
#import <sqlite3.h>
#import <UIKit/UIKit.h>
#import <UIKit/UIApplication.h>
#import <CommonCrypto/CommonHMAC.h>
#import <SpringBoard/SBApplicationController.h>
#import <SpringBoard/SBApplication.h>
#import <SpringBoard/SBTelephonyManager.h>
#import <Preferences/PSRootController.h>
#import <Preferences/PSDetailController.h>
#include "KeychainUtils.h"
#include "NSData+Base64.h"
#include "TwitterAuth.h"
#include "../../SDK/Plugin.h"

@interface UIScreen (LIAdditions)

-(float) scale;

@end

Class $SBTelephonyManager = objc_getClass("SBTelephonyManager");

#define Hook(cls, sel, imp) \
        _ ## imp = MSHookMessage($ ## cls, @selector(sel), &$ ## imp)

@interface TwitterAuthController : PSDetailController <UIWebViewDelegate, UIAlertViewDelegate>

@property (nonatomic, retain) UIWebView* webView;
@property (nonatomic, retain) UIActivityIndicatorView* activity;
@property (retain) TwitterAuth* auth;

@end

@implementation TwitterAuthController

@synthesize webView, activity;
@synthesize auth;

- (void) loadURL:(NSURL*) url
{
	self.activity = [[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite] autorelease];

	UIView* view = [self view];
	view.autoresizingMask = (UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight);
	view.autoresizesSubviews = YES;

	self.webView = [[UIWebView alloc] initWithFrame:view.bounds];
	self.webView.autoresizesSubviews = YES;
	self.webView.autoresizingMask=(UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth);
	self.webView.scalesPageToFit = YES;
	self.webView.delegate = self;
	[view addSubview:self.webView];

	[self.webView loadRequest:[NSURLRequest requestWithURL:url]];
}

-(void) initAuth
{
	if (self.auth == nil)
	{
		self.auth = [[[TwitterAuth alloc] init] autorelease];
		if ([self.auth requestTwitterToken])
			[self loadURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://api.twitter.com/oauth/authorize?oauth_token=%@", self.auth.oauth_token]]];
		else
			NSLog(@"LI:Twitter: Token request failed!");
	}
}

-(void) viewWillBecomeVisible:(id) spec
{
	[super viewWillBecomeVisible:spec];
	[self initAuth];
}

-(void) viewWillAppear:(BOOL) a
{
	[super viewWillAppear:a];
	[self.view bringSubviewToFront:self.webView];
	[self initAuth];
}

-(void) setBarButton:(UIBarButtonItem*) button
{
	PSRootController* root = self.rootController;
	UINavigationBar* bar = root.navigationBar;
	UINavigationItem* item = bar.topItem;
	item.rightBarButtonItem = button;
}

-(void) startLoad:(UIWebView*) wv
{
	CGRect r = self.activity.frame;
	r.size.width += 5;
	UIView* v = [[[UIView alloc] initWithFrame:r] autorelease];
	v.backgroundColor = [UIColor clearColor];
	[v addSubview:self.activity];
	[self.activity startAnimating];
	UIBarButtonItem* button = [[[UIBarButtonItem alloc] initWithCustomView:v] autorelease];
	[self setBarButton:button];

	UIApplication* app = [UIApplication sharedApplication];
	app.networkActivityIndicatorVisible = YES;
}

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType
{
	if ([request.URL.scheme isEqualToString:@"http"])
	{	
		if ([self.auth authorizeTwitterToken])
			NSLog(@"LI:Twitter: Authorized!");
		else
			NSLog(@"LI:Twitter: Authorization failed!");

		if ([self.rootController respondsToSelector:@selector(popControllerWithAnimation:)])
                	[self.rootController popControllerWithAnimation:YES];
		else
                	[self.rootController popViewControllerAnimated:YES];

		return NO;
	}

	[self startLoad:webView];
	return YES;
}

-(void) webViewDidFinishLoad:(UIWebView*) wv
{
	[self.activity stopAnimating];
	[self setBarButton:[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:wv action:@selector(reload)] autorelease]];

	UIApplication* app = [UIApplication sharedApplication];
	app.networkActivityIndicatorVisible = NO;
}

-(id) navigationTitle
{
	return @"Authentication";
}

@end

@interface UIProgressIndicator : UIView

+(CGSize) defaultSizeForStyle:(int) size;
-(void) setStyle:(int) style;

@end

extern "C" CFStringRef UIDateFormatStringForFormatType(CFStringRef type);

#define localize(str) \
        [self.plugin.bundle localizedStringForKey:str value:str table:nil]

#define localizeSpec(str) \
        [self.bundle localizedStringForKey:str value:str table:nil]

#define localizeGlobal(str) \
        [self.plugin.globalBundle localizedStringForKey:str value:str table:nil]

static NSString* TWITTER_SERVICE = @"com.ashman.lockinfo.TwitterPlugin";

static NSInteger sortByDate(id obj1, id obj2, void* context)
{
        double d1 = [[obj1 objectForKey:@"date"] doubleValue];
        double d2 = [[obj2 objectForKey:@"date"] doubleValue];

        if (d1 < d2)
                return NSOrderedDescending;
        else if (d1 > d2)
                return NSOrderedAscending;
        else
                return NSOrderedSame;
}


@interface TweetView : UIView

@property (nonatomic, retain) NSString* name;
@property (nonatomic, retain) NSString* tweet;
@property (nonatomic, retain) NSString* time;
@property (nonatomic, retain) UIImage* image;
@property (nonatomic) BOOL directMessage;
@property (nonatomic, retain) LITheme* theme;

@end

static UIImage* directMessageIcon;

@interface UIKeyboard : NSObject

+ (CGSize) defaultSize;

@end

@implementation TweetView

@synthesize name, time, image, theme, tweet, directMessage;

-(void) setFrame:(CGRect) r
{
	[super setFrame:r];
	[self setNeedsDisplay];
}

-(void) drawRect:(CGRect) rect
{
	CGRect r = self.superview.bounds;

	NSString* name = self.name;
        CGSize nameSize = [name sizeWithFont:self.theme.summaryStyle.font];
	CGRect imageRect = CGRectMake(5, 5, (int)(nameSize.height * 1.4), (int)(nameSize.height * 1.4));

	NSString* padding = stringPaddingWithFont(self.theme.detailStyle.font, imageRect.origin.x + imageRect.size.width + 4);
	CGSize paddingSize = [padding sizeWithFont:self.theme.detailStyle.font];

	NSString* text = [padding stringByAppendingString:self.tweet];

	[name drawInRect:CGRectMake(5 + paddingSize.width, 0, nameSize.width, nameSize.height) withLIStyle:self.theme.summaryStyle lineBreakMode:UILineBreakModeTailTruncation];

	LIStyle* timeStyle = [self.theme.detailStyle copy];
	timeStyle.font = [UIFont systemFontOfSize:self.theme.detailStyle.font.pointSize];
	CGSize timeSize = [self.time sizeWithFont:timeStyle.font];
	[self.time drawInRect:CGRectMake(r.size.width - timeSize.width - 5, nameSize.height - timeSize.height, timeSize.width, timeSize.height) withLIStyle:timeStyle lineBreakMode:UILineBreakModeClip alignment:UITextAlignmentRight];
	[timeStyle release];

        CGSize s = [text sizeWithFont:self.theme.detailStyle.font constrainedToSize:CGSizeMake(r.size.width - 10, 4000) lineBreakMode:UILineBreakModeWordWrap];
	[text drawInRect:CGRectMake(5, nameSize.height, s.width, s.height) withLIStyle:self.theme.detailStyle lineBreakMode:UILineBreakModeWordWrap];

	[self.image drawInRoundedRect:imageRect withRadius:3];

	if (self.directMessage)
	{
		CGRect iconRect = CGRectMake(imageRect.origin.x + imageRect.size.width + 3 - directMessageIcon.size.width, imageRect.origin.y + imageRect.size.height + 3 - directMessageIcon.size.height, directMessageIcon.size.width, directMessageIcon.size.height);
		[directMessageIcon drawInRect:iconRect];
	}
}

@end

static NSNumber* YES_VALUE = [NSNumber numberWithBool:YES];

@interface TwitterPlugin : UIViewController <LIPluginController, LITableViewDelegate, UITableViewDataSource, UITextViewDelegate, LIPreviewDelegate> 
{
	NSTimeInterval nextUpdate;
	NSDateFormatter* formatter;
	NSConditionLock* lock;
}

@property (nonatomic, retain) LIPlugin* plugin;
@property (retain) NSMutableArray* tweets;
@property (retain) NSMutableDictionary* imageCache;
@property (nonatomic, retain) UINavigationController* previewController;
@property (nonatomic, retain) UILabel* countLabel;

@property (retain) NSMutableDictionary* tempTweets;
@property (retain) NSMutableDictionary* currentTweet;
@property (retain) NSMutableString* xml;
@property (retain) NSString* type;

@property (nonatomic, retain) UIView* newTweetView;

// preview stuff
@property (nonatomic, retain) NSDictionary* previewTweet;
@property (nonatomic, retain) UITextView* previewTextView;

@end

@implementation TwitterPlugin

@synthesize tweets, tempTweets, xml, plugin, imageCache, type, currentTweet, previewController, countLabel;

@synthesize previewTweet, previewTextView, newTweetView;

-(void) setCount:(int) count
{
	self.countLabel.text = [[NSNumber numberWithInt:count] stringValue];
}

-(void) previewDidShow:(LIPreview*) preview
{
	[self.previewTextView becomeFirstResponder];
}

-(void) loadView
{
	UIView* v = [[[UIView alloc] initWithFrame:[[UIScreen mainScreen] applicationFrame]] autorelease];
	v.backgroundColor = [UIColor blackColor];

	UITextView* tv = [[[UITextView alloc] initWithFrame:v.bounds] autorelease];
	tv.backgroundColor = [UIColor blackColor];
	tv.editable = true;
	tv.keyboardAppearance = UIKeyboardAppearanceAlert;
	tv.font = [UIFont systemFontOfSize:20];
	tv.textColor = [UIColor whiteColor];

	if (NSString* name = [self.previewTweet objectForKey:@"screenName"])
		tv.text = [NSString stringWithFormat:@"@%@ ", name];

	tv.delegate = self;
	[v addSubview:tv];
	self.previewTextView = tv;

	UILabel* l = [[[UILabel alloc] initWithFrame:CGRectMake(v.frame.size.width - 60, v.frame.size.height - [UIKeyboard defaultSize].height - 80, 60, 30)] autorelease];
	l.backgroundColor = [UIColor clearColor];
	l.font = [UIFont boldSystemFontOfSize:24];
	l.textColor = [UIColor whiteColor];
	l.textAlignment = UITextAlignmentCenter;
	self.countLabel = l;
	[v addSubview:l];

	[self setCount:140 - tv.text.length];
	self.view = v;
}

- (BOOL) keyboardInputShouldDelete:(UITextView*)input
{
	[self setCount:140 - input.text.length];
       	return YES;
}

-(void) sendTweet:(NSString*) tweet
{
        UIProgressIndicator* ind = [[[UIProgressIndicator alloc] initWithFrame:CGRectMake(0, 0, 14, 14)] autorelease];
	ind.tag = 575933;
        ind.center = self.newTweetView.center;
        [ind setStyle:1];
	[ind startAnimation];

	self.newTweetView.hidden = YES;
	[self.newTweetView.superview addSubview:ind];

	[self performSelectorInBackground:@selector(sendTweetInBackground:) withObject:tweet];
}


-(void) sendTweetInBackground:(NSString*) tweet
{
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

	NSString* url = @"https://api.twitter.com/1/statuses/update.xml";

	NSMutableDictionary* params = [NSMutableDictionary dictionaryWithObjectsAndKeys:tweet, @"status", nil];
	if (NSString* id = [self.previewTweet objectForKey:@"id"])
		[params setValue:id forKey:@"in_reply_to_status_id"];

	NSMutableArray* paramArray = [NSMutableArray arrayWithCapacity:params.count];
	for (id key in params)
		[paramArray addObject:[NSString stringWithFormat:@"%@=%@", [key encodedURLParameterString], [[params objectForKey:key] encodedURLParameterString]]];
	NSString* qs = [paramArray componentsJoinedByString:@"&"];

	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
	[request setHTTPMethod:@"POST"];
	NSData* body = [qs dataUsingEncoding:NSUTF8StringEncoding];

	TwitterAuth* auth = [[[TwitterAuth alloc] init] autorelease];
	NSString* header = [auth OAuthorizationHeader:request.URL method:@"POST" body:body];
	[request setValue:header forHTTPHeaderField:@"Authorization"];
	[request setHTTPBody:body];

	NSError* error;
	NSData* data = [NSURLConnection sendSynchronousRequest:request returningResponse:NULL error:&error];

	[[self.newTweetView.superview viewWithTag:575933] removeFromSuperview];
	self.newTweetView.hidden = NO;

	[pool release];
}

-(void) dismissTweet
{
	[self.previewTextView resignFirstResponder];
	[self.plugin dismissPreview];
}

-(void) sendButtonPressed
{
	[self sendTweet:self.previewTextView.text];
	[self dismissTweet];
}

- (BOOL) keyboardInput:(UITextView*)input shouldInsertText:(NSString *)text isMarkedText:(int)marked 
{
	if (input.text.length == 140)
		return NO;

	[self setCount:140 - input.text.length - text.length];
       	return YES;
}

-(UIView*) showTweet:(NSDictionary*) tweet
{
	self.navigationItem.title = localize(@"Twitter");
	self.navigationItem.leftBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:localizeGlobal(@"Cancel") style:UIBarButtonItemStyleBordered target:self action:@selector(dismissTweet)] autorelease];
	self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:localizeGlobal(@"Send") style:UIBarButtonItemStyleDone target:self action:@selector(sendButtonPressed)] autorelease];

	self.previewTweet = tweet;

	if (self.isViewLoaded)
	{
		if (NSString* name = [self.previewTweet objectForKey:@"screenName"])
			self.previewTextView.text = [NSString stringWithFormat:@"@%@ ", name];
		else
			self.previewTextView.text = @"";

		[self setCount:140 - self.previewTextView.text.length];
		[self.previewTextView becomeFirstResponder];
	}

	self.previewController = [[[UINavigationController alloc] initWithRootViewController:self] autorelease];
	UINavigationBar* bar = self.previewController.navigationBar;
	bar.barStyle = UIBarStyleBlackOpaque;

	return self.previewController.view;
}

-(void) showNewTweet
{
	UIView* v = [self showTweet:[NSDictionary dictionary]];
	[self.plugin showPreview:v];
}

-(UIView*) tableView:(LITableView*) tableView previewWithFrame:(CGRect) frame forRowAtIndexPath:(NSIndexPath*) indexPath
{
	BOOL newTweets = YES;
	if (NSNumber* n = [self.plugin.preferences objectForKey:@"NewTweets"])
		newTweets = n.boolValue;
 
	int row = indexPath.row - (newTweets ? 1 : 0);
	if (row < self.tweets.count)
	{
		BOOL replies = YES;
		if (NSNumber* n = [self.plugin.preferences objectForKey:@"Replies"])
			replies = n.boolValue;
 
		if (replies)
			return [self showTweet:[self.tweets objectAtIndex:row]];
		else
			return nil;
	}
	else
	{
		return [self showTweet:[NSDictionary dictionary]];
	}
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
	if ([elementName isEqualToString:@"text"] || 
		[elementName isEqualToString:@"created_at"] || 
		[elementName isEqualToString:@"profile_image_url"] || 
		[elementName isEqualToString:@"name"] || 
		[elementName isEqualToString:@"id"] || 
		[elementName isEqualToString:@"screen_name"])
	{
		self.xml = [NSMutableString stringWithCapacity:40];
	}
	else if ([elementName isEqualToString:@"status"] || 
			[elementName isEqualToString:@"direct_message"])
	{
		self.currentTweet = [NSMutableDictionary dictionaryWithCapacity:2];
		[self.currentTweet setValue:YES_VALUE forKey:self.type];
	}
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
	if ([elementName isEqualToString:@"text"])
	{
		[self.currentTweet setValue:self.xml forKey:@"tweet"];
	}
	else if ([elementName isEqualToString:@"id"])
	{
		if ([self.currentTweet objectForKey:@"id"] == nil)
		{
			[self.currentTweet setValue:self.xml forKey:@"id"];
			[self.currentTweet setValue:YES_VALUE forKey:self.type];

			if (NSMutableDictionary* t = [self.tempTweets objectForKey:self.xml])
				[t setValue:YES_VALUE forKey:self.type];
			else
				[self.tempTweets setValue:self.currentTweet forKey:self.xml];
		}
	}
	else if ([elementName isEqualToString:@"name"])
	{
		if ([self.currentTweet objectForKey:@"name"] == nil)
		{
			[self.currentTweet setValue:self.xml forKey:@"name"];
		}
	}
	else if ([elementName isEqualToString:@"screen_name"])
	{
		if ([self.currentTweet objectForKey:@"screenName"] == nil)
		{
			[self.currentTweet setValue:self.xml forKey:@"screenName"];
		}
	}
	else if ([elementName isEqualToString:@"profile_image_url"])
	{
		if ([self.currentTweet objectForKey:@"image"] == nil)
		{
			NSString* url = [[self.xml copy] autorelease];
			if (url)
			{
				[self.currentTweet setValue:url forKey:@"image"];
				[self.imageCache setValue:[[[UIImage alloc] initWithData:[NSData dataWithContentsOfURL:[NSURL URLWithString:url]]] autorelease] forKey:url];
			}
		}
	}
	else if ([elementName isEqualToString:@"created_at"])
	{
		if ([self.currentTweet objectForKey:@"date"] == nil)
		{
			NSDate* d = [formatter dateFromString:self.xml];
			NSTimeInterval time = [d timeIntervalSince1970];
			[self.currentTweet setValue:[NSNumber numberWithDouble:time] forKey:@"date"];
		}
	}

	self.xml = nil;
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string
{
	if (self.xml)
		[self.xml appendString:string];
}

- (CGFloat)tableView:(LITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
	BOOL newTweets = YES;
	if (NSNumber* n = [self.plugin.preferences objectForKey:@"NewTweets"])
		newTweets = n.boolValue;

	if (newTweets && indexPath.row == 0)
		return 24;

	int row = indexPath.row - (newTweets ? 1 : 0);
	if (row >= self.tweets.count)
		return 0;

	NSDictionary* elem = [self.tweets objectAtIndex:row];
        NSString* text = [elem objectForKey:@"tweet"];

	text = [@"         " stringByAppendingString:text];
		
	int width = tableView.frame.size.width - 10;
        CGSize s = [text sizeWithFont:tableView.theme.detailStyle.font constrainedToSize:CGSizeMake(width, 480) lineBreakMode:UILineBreakModeWordWrap];
        return (s.height + tableView.theme.summaryStyle.font.pointSize + 8);
}

- (NSInteger)tableView:(UITableView *)tableView numberOfItemsInSection:(NSInteger)section 
{
	int max = 5;
	if (NSNumber* n = [self.plugin.preferences objectForKey:@"MaxTweets"])
		max = n.intValue;

	return (self.tweets.count > max ? max : self.tweets.count);
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section 
{
	BOOL newTweets = YES;
	if (NSNumber* n = [self.plugin.preferences objectForKey:@"NewTweets"])
		newTweets = n.boolValue;

	return [self tableView:tableView numberOfItemsInSection:section] + (newTweets ? 1 : 0);
}

- (UITableViewCell *)tableView:(LITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath 
{
	BOOL newTweets = YES;
	if (NSNumber* n = [self.plugin.preferences objectForKey:@"NewTweets"])
		newTweets = n.boolValue;

	int row = indexPath.row;
	if (newTweets)
	{
		if (row == 0)
		{
			UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"NewTweetCell"];
			if (cell == nil) 
			{
				CGRect frame = CGRectMake(0, -1, tableView.frame.size.width, 24);
				cell = [[[UITableViewCell alloc] initWithFrame:frame reuseIdentifier:@"NewTweetCell"] autorelease];

				UIImageView* iv = [[[UIImageView alloc] initWithImage:tableView.sectionSubheader] autorelease];
				iv.autoresizingMask = UIViewAutoresizingFlexibleWidth;
				iv.frame = frame;
				[cell.contentView addSubview:iv];

				UIView* container = [[[UIView alloc] initWithFrame:frame] autorelease];
				container.backgroundColor = [UIColor clearColor];
				container.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
				[cell.contentView addSubview:container];

				int fontSize = tableView.theme.headerStyle.font.pointSize + 3;
				LILabel* l = [tableView labelWithFrame:frame];
				l.tag = 456789;
				l.backgroundColor = [UIColor clearColor];
				l.style = tableView.theme.headerStyle;
				l.text = localize(@"Compose");
				l.textAlignment = UITextAlignmentCenter;
				[container addSubview:l];

				CGSize sz = [l.text sizeWithFont:l.style.font];
				UIImage* img = [UIImage li_imageWithContentsOfResolutionIndependentFile:[self.plugin.bundle pathForResource:@"LITwitterTweet" ofType:@"png"]];
				UIImageView* niv = [[[UIImageView alloc] initWithImage:img] autorelease];
				CGRect r = niv.frame;
				r.origin.x = (frame.size.width / 2) + (int)(sz.width / 2) + 4;
				r.origin.y = 2;
				niv.frame = r;
				self.newTweetView = niv;
				[container addSubview:niv];
			}

			[[cell viewWithTag:456789] setStyle:tableView.theme.headerStyle];

			return cell;
		}
		
		row--;
	}

	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"TweetCell"];
	
	if (cell == nil) 
	{
		CGRect frame = CGRectMake(0, 0, tableView.frame.size.width, 24);
		cell = [[[UITableViewCell alloc] initWithFrame:frame reuseIdentifier:@"TweetCell"] autorelease];
		
		TweetView* v = [[[TweetView alloc] initWithFrame:frame] autorelease];
		v.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		v.backgroundColor = [UIColor clearColor];
		v.tag = 57;
		[cell.contentView addSubview:v];
	}

	TweetView* v = [cell.contentView viewWithTag:57];
	v.theme = tableView.theme;
	v.frame = CGRectMake(0, 0, tableView.frame.size.width, [self tableView:tableView heightForRowAtIndexPath:indexPath]);
	v.name = nil;
	v.tweet = nil;
	v.time = nil;

	if (row < self.tweets.count)
	{	
		NSDictionary* elem = [self.tweets objectAtIndex:row];
		v.tweet = [elem objectForKey:@"tweet"];
	
		BOOL screenNames = false;
		if (NSNumber* b = [self.plugin.preferences objectForKey:@"UseScreenNames"])
			screenNames = b.boolValue;
		v.name = [elem objectForKey:(screenNames ? @"screenName" : @"name")];
		v.image = [self.imageCache objectForKey:[elem objectForKey:@"image"]];
		v.directMessage = ([elem objectForKey:@"directMessage"] != nil);
       	 
		NSNumber* dateNum = [elem objectForKey:@"date"];
		int diff = 0 - [[NSDate dateWithTimeIntervalSince1970:dateNum.doubleValue] timeIntervalSinceNow];
		if (diff > 86400)
		{
			int n = (int)(diff / 86400);
			v.time = (n == 1 ? @"1 day ago" : [NSString stringWithFormat:localize(@"%d days ago"), n]);
		}
		else if (diff > 3600)
		{
			int n = (int)(diff / 3600);
			if (diff % 3600 > 1800)
				n++;

			v.time = (n == 1 ? @"about 1 hour ago" : [NSString stringWithFormat:localize(@"about %d hours ago"), n]);
		}
		else if (diff > 60)
		{
			int n = (int)(diff / 60);
			if (diff % 60 > 30)
				n++;

			v.time = (n == 1 ? @"1 minute ago" : [NSString stringWithFormat:localize(@"%d minutes ago"), n]);
		}
		else
		{
			v.time = (diff == 1 ? @"1 second ago" : [NSString stringWithFormat:localize(@"%d seconds ago"), diff]);
		}
	}
	
	[v setNeedsDisplay];
	return cell;

}

/*
MSHook(BOOL, handleKeyEvent, id self, SEL sel, id event)
{
	if (previewTextView)
		return NO;
	else
		return _handleKeyEvent(self, sel, event);
}
*/

static void callInterruptedApp(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo)
{
	NSLog(@"LI:Twitter: Call interrupted app");
}

static void activeCallStateChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo)
{
	NSLog(@"LI:Twitter: Call state changed");
}

-(id) initWithPlugin:(LIPlugin*) plugin
{
	self = [super init];
	self.plugin = plugin;
	self.imageCache = [NSMutableDictionary dictionaryWithCapacity:10];
	self.tweets = [NSMutableArray arrayWithCapacity:10];
	self.tempTweets = [NSMutableDictionary dictionaryWithCapacity:20];

	lock = [[NSConditionLock alloc] init];
	formatter = [[NSDateFormatter alloc] init];
	formatter.locale = [[[NSLocale alloc] initWithLocaleIdentifier:@"en_US"] autorelease];
	formatter.dateFormat = @"EEE MMM dd HH:mm:ss Z yyyy";

	plugin.tableViewDataSource = self;
	plugin.tableViewDelegate = self;
	plugin.previewDelegate = self;

	NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
	[center addObserver:self selector:@selector(update:) name:LITimerNotification object:nil];
	[center addObserver:self selector:@selector(update:) name:LIViewReadyNotification object:nil];

//	Class $SBAwayController = objc_getClass("SBAwayController");
//	Hook(SBAwayController, handleKeyEvent:, handleKeyEvent);

	if (directMessageIcon)
		[directMessageIcon release];

	directMessageIcon = [[UIImage li_imageWithContentsOfResolutionIndependentFile:[self.plugin.bundle pathForResource:@"LITwitterDirectMessage" ofType:@"png"]] retain];

	return self;
}

-(void) dealloc
{
	[formatter release];
	[lock release];
	[super dealloc];
}

-(void) loadTweets:(NSString*) url parameters:(NSDictionary*) parameters
{
	NSString* fullURL = url;
	if (parameters.count > 0)
	{
		NSMutableArray* paramArray = [NSMutableArray arrayWithCapacity:parameters.count];
		for (id key in parameters)
			[paramArray addObject:[NSString stringWithFormat:@"%@=%@", key, [parameters objectForKey:key]]];

		fullURL = [fullURL stringByAppendingFormat:@"?%@", [paramArray componentsJoinedByString:@"&"]];
	}

	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:fullURL]];
	request.HTTPMethod = @"GET";

	TwitterAuth* auth = [[[TwitterAuth alloc] init] autorelease];
	if (!auth.authorized)
	{
		NSLog(@"LI:Twitter: Twitter client is not authorized!");
		return;
	}

	NSString* header = [auth OAuthorizationHeader:request.URL method:@"GET" body:nil];
	[request setValue:header forHTTPHeaderField:@"Authorization"];

	NSData* data = [NSURLConnection sendSynchronousRequest:request returningResponse:NULL error:NULL];
//	NSLog(@"LI:Twitter: Tweet data: %@", [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease]);

	NSXMLParser* parser = [[NSXMLParser alloc] initWithData:data];
	parser.delegate = self;

	@try
	{
		[parser parse];
	}
	@catch (id err)
	{
		NSLog(@"LI:Twitter: Error loading tweets: %@", err);
	}

	[parser release];
}

-(void) _updateTweets
{	
	if (SBTelephonyManager* mgr = [$SBTelephonyManager sharedTelephonyManager])
	{
                if (mgr.inCall || mgr.incomingCallExists)
		{
			NSLog(@"LI:Twitter: No data connection available.");
                        return;
		}
	}

	NSLog(@"LI:Twitter: Loading tweets...");

	int count = 5;
	if (NSNumber* n = [self.plugin.preferences objectForKey:@"MaxTweets"])
		count = n.intValue;

	BOOL showFriends = true;
	if (NSNumber* n = [self.plugin.preferences objectForKey:@"ShowFriends"])
		showFriends = n.boolValue;

	if (showFriends)
	{
		self.type = @"friend";
		[self loadTweets:@"https://api.twitter.com/statuses/home_timeline.xml" parameters:[NSDictionary dictionaryWithObjectsAndKeys:[NSString stringWithFormat:@"%d", count+1], @"count", nil]];
	}

	BOOL showMentions = true;
	if (NSNumber* n = [self.plugin.preferences objectForKey:@"ShowMentions"])
		showMentions = n.boolValue;

	if (showMentions)
	{
		self.type = @"mention";
		[self loadTweets:@"https://api.twitter.com/statuses/mentions.xml" parameters:[NSDictionary dictionaryWithObjectsAndKeys:[NSString stringWithFormat:@"%d", count+1], @"count", nil]];
	}

	BOOL showDMs = true;
	if (NSNumber* n = [self.plugin.preferences objectForKey:@"ShowDirectMessages"])
		showDMs = n.boolValue;

	if (showDMs)
	{
		self.type = @"directMessage";
		[self loadTweets:@"https://api.twitter.com/1/direct_messages.xml" parameters:[NSDictionary dictionaryWithObjectsAndKeys:[NSString stringWithFormat:@"%d", count+1], @"count", nil]];
	}

	NSArray* sorted = [self.tempTweets.allValues sortedArrayUsingFunction:sortByDate context:nil];
//	NSLog(@"LI:Twitter: Tweets: %@", sorted);
	if (sorted.count != 0 && ![sorted isEqualToArray:self.tweets])
	{
		[self.tweets setArray:sorted];

		NSMutableDictionary* dict = [NSMutableDictionary dictionaryWithCapacity:1];
		[dict setValue:self.tweets forKey:@"tweets"];  
		[self.plugin updateView:dict];
	}

	[self.tempTweets removeAllObjects];
	self.currentTweet = nil;
	self.xml = nil;
	
	NSTimeInterval refresh = 900;
	if (NSNumber* n = [self.plugin.preferences objectForKey:@"RefreshInterval"])
		refresh = n.intValue;

	nextUpdate = [[NSDate dateWithTimeIntervalSinceNow:refresh] timeIntervalSinceReferenceDate];
}

- (void) updateTweets:(BOOL) force
{
	if (!self.plugin.enabled)
		return;

	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

	if ([lock tryLock])
	{
		if(force || nextUpdate < [NSDate timeIntervalSinceReferenceDate])
			[self _updateTweets];

		[lock unlock];
	}

	[pool release];
}

- (void) update:(NSNotification*) notif
{
	[self updateTweets:NO];
}

- (void) tableView:(LITableView*) tableView reloadDataInSection:(NSInteger)section
{
	[self updateTweets:YES];
}

@end
