#import <Foundation/Foundation.h>
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
#import <QuartzCore/QuartzCore.h>
#include "KeychainUtils.h"
#include "NSData+Base64.h"
#include "TwitterAuth.h"
#include "Plugin.h"

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

@interface UIKeyboardImpl : UIView
@property (nonatomic, retain) id delegate;
@end

@interface UIKeyboard : UIView

+(UIKeyboard*) activeKeyboard;
+(void) initImplementationNow;
+(CGSize) defaultSize;

@end


static NSNumber* YES_VALUE = [NSNumber numberWithBool:YES];
static int selectedIndex = 0;
static BOOL WRITE_MODE  = YES;
static NSString * const RT_IDENTIFIER_TEXT = @"_li__tp___rt____id_____";
static UITextView* previewTextView;
#define UIColorFromRGB(rgbValue) [UIColor colorWithRed:((float)((rgbValue & 0xFF0000) >> 16))/255.0 green:((float)((rgbValue & 0xFF00) >> 8))/255.0 blue:((float)(rgbValue & 0xFF))/255.0 alpha:1.0]

@interface TwitterPlugin : UIViewController <LIPluginController, LITableViewDelegate, UITableViewDataSource, UITextViewDelegate, LIPreviewDelegate> 
{
	NSTimeInterval nextUpdate;
	NSDateFormatter* formatter;
	NSConditionLock* lock;
}

@property (nonatomic, retain) LIPlugin* plugin;
@property (retain) NSMutableArray* tweets;
@property (retain) NSMutableArray* homeline;
@property (retain) NSMutableArray* mentions;
@property (retain) NSMutableArray* directMessages;
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
@property (nonatomic, retain) UIWebView* webView;

@property (nonatomic, retain) UIView* editView;
@property (nonatomic, retain) UIView* readView;
@property (nonatomic, retain) UIActivityIndicatorView* activity;


@end

@implementation TwitterPlugin

@synthesize tweets, homeline, mentions, directMessages, tempTweets, xml, plugin, imageCache, type, currentTweet, previewController, countLabel;

@synthesize previewTweet, previewTextView, newTweetView, webView, editView, readView, activity;

-(void) setCount:(int) count
{
	self.countLabel.text = [[NSNumber numberWithInt:count] stringValue];
}
/*
 - (BOOL)textViewShouldBeginEditing:(UITextView *)textView{
 return YES;
 }
 */
-(void) previewWillDismiss:(LIPreview*) preview
{
    [self.previewTextView resignFirstResponder];
    [self hideKeyboard];
}
-(void) previewDidShow:(LIPreview*) preview
{
    if(WRITE_MODE)
    {
        [self.previewTextView becomeFirstResponder];
        [self showKeyboard];
    }
    else
    {
        [self.previewTextView resignFirstResponder];
        [self hideKeyboard];
    }
}

-(void) showKeyboard
{
	if (Class peripheral = objc_getClass("UIPeripheralHost"))
    {
        [[peripheral sharedInstance] setAutomaticAppearanceEnabled:YES];
        [[peripheral sharedInstance] orderInAutomatic];
    }
    else
    {
        [[UIKeyboard automaticKeyboard] orderInWithAnimation:YES];
    }
}

-(void) hideKeyboard
{
    if (Class peripheral = objc_getClass("UIPeripheralHost"))
    {
        [[peripheral sharedInstance] orderOutAutomatic];
        [[peripheral sharedInstance] setAutomaticAppearanceEnabled:NO];
    }
    else
    {
        [[UIKeyboard automaticKeyboard] orderOutWithAnimation:YES];
    }
}

-(void) loadView
{
    
	UIView* v = [[[UIView alloc] initWithFrame:[[UIScreen mainScreen] applicationFrame]] autorelease];
	v.backgroundColor = [UIColor blackColor];
    
    UIView* editView = [[[UIView alloc] initWithFrame:v.bounds] autorelease];
	editView.backgroundColor = [UIColor blackColor];
    
	UITextView* tv = [[[UITextView alloc] initWithFrame:v.bounds] autorelease];
	tv.backgroundColor = [UIColor blackColor];
	tv.editable = YES;
    tv.userInteractionEnabled = YES;
	tv.keyboardAppearance = UIKeyboardAppearanceAlert;
	tv.font = [UIFont systemFontOfSize:20];
	tv.textColor = [UIColor whiteColor];
   	tv.delegate = self;
    [editView addSubview:tv];
    self.previewTextView = tv;
    
	UILabel* countLbl = [[[UILabel alloc] initWithFrame:CGRectMake(v.frame.size.width - 60, v.frame.size.height - [UIKeyboard defaultSize].height - 80, 60, 30)] autorelease];
	countLbl.backgroundColor = [UIColor clearColor];
	countLbl.font = [UIFont boldSystemFontOfSize:24];
	countLbl.textColor = [UIColor whiteColor];
	countLbl.textAlignment = UITextAlignmentCenter;
    [editView addSubview:countLbl];
    self.countLabel = countLbl;
    
    UIView* readView = [[[UIView alloc] initWithFrame:v.bounds] autorelease];
	readView.backgroundColor = UIColorFromRGB(0xC5CCd4);
    
    UIImageView* profImg = [[[UIImageView alloc] initWithImage:[self.imageCache objectForKey:@""]] autorelease];
    profImg.frame = CGRectMake(10, 15, 48, 48);
    profImg.tag = 100;
    CALayer *layer = [profImg layer];
    layer.masksToBounds = NO;
    layer.cornerRadius = 4.0;
    layer.borderWidth = 1.0;
    layer.borderColor = [[UIColor clearColor] CGColor];
    layer.shadowColor = [UIColorFromRGB(0x666666) CGColor];
    layer.shadowOffset = CGSizeMake(1, 1);
    layer.shadowOpacity = 1;
    layer.shadowRadius = 4.0;
    [readView addSubview:profImg];
    
    UILabel* nameLbl = [[[UILabel alloc] initWithFrame:CGRectMake(70, 10, 250, 48)] autorelease];
    nameLbl.font = [UIFont boldSystemFontOfSize:18];
    nameLbl.backgroundColor = [UIColor clearColor];
    nameLbl.textColor = [UIColor blackColor];
    nameLbl.textAlignment = UITextAlignmentLeft;
    nameLbl.shadowColor = UIColorFromRGB(0xFFFFFF);
    nameLbl.shadowOffset = CGSizeMake(0, 1.0);
    nameLbl.lineBreakMode = UILineBreakModeTailTruncation;
    nameLbl.tag = 101;
    [readView addSubview:nameLbl];
    
    UILabel* screenLbl = [[[UILabel alloc] initWithFrame:CGRectMake(70, 30, 250, 48)] autorelease];
    screenLbl.font = [UIFont systemFontOfSize:14];
    screenLbl.backgroundColor = [UIColor clearColor];
    screenLbl.textColor = [UIColor blackColor];
    screenLbl.textAlignment = UITextAlignmentLeft;
    screenLbl.shadowColor = UIColorFromRGB(0xFFFFFF);
    screenLbl.shadowOffset = CGSizeMake(0, 1.0);
    screenLbl.lineBreakMode = UILineBreakModeTailTruncation;
    screenLbl.tag = 102;
    [readView addSubview:screenLbl];
    
    UIWebView* webView = [[[UIWebView alloc] initWithFrame:CGRectMake(-1, 75, v.frame.size.width + 1, v.frame.size.height - 75)] autorelease];
    webView.delegate = self;
    webView.dataDetectorTypes = (UIDataDetectorTypeLink | UIDataDetectorTypePhoneNumber);
    layer = [webView layer];
    layer.masksToBounds = NO;
    layer.shadowColor = [UIColorFromRGB(0x999999) CGColor];
    layer.shadowOffset = CGSizeMake(0, -4);
    layer.shadowOpacity = 0.2;
    layer.shadowRadius = 10;
    layer.borderWidth = 1.0;
    layer.borderColor = [UIColorFromRGB(0X999999) CGColor];
    
    [readView addSubview:webView];
    self.activity = [[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray] autorelease];
    self.activity.center = CGPointMake(readView.frame.size.width / 2 , 90.0);
    self.activity.hidesWhenStopped = YES;
    [readView addSubview:self.activity];
    
    self.webView = webView;
    
    self.editView = editView;
    self.readView = readView;
    
	[self setCount:140 - tv.text.length];
    [v addSubview:readView];
    [v addSubview:editView];    
	self.view = v;
    
    if (NSString* name = [self.previewTweet objectForKey:@"screenName"]){
        [self fillDetailView:self.previewTweet];
        [self switchToReadView];
    }else{
        [self switchToWriteView];
    }
    
}

-(void)fillDetailView:(NSDictionary *) tweet
{
    
    if (NSString* name = [tweet objectForKey:@"name"]){
        name = [tweet objectForKey:@"name"];
        NSString *screenName = [NSString stringWithFormat:@"@%@", [tweet objectForKey:@"screenName"]];
        
        NSString *imageUrl = [tweet objectForKey:@"image"];
        
        UIImageView* profImg = [self.readView viewWithTag:100]; //img view
        [profImg setImage:[self.imageCache objectForKey:imageUrl]];
        [profImg setNeedsDisplay];
        
        UILabel* nameLbl = [self.readView viewWithTag:101]; //name lbl
        nameLbl.text = name;
        [nameLbl setNeedsDisplay];
        
        UILabel* screenLbl = [self.readView viewWithTag:102]; //screenname lbl
        screenLbl.text = screenName;
        [screenLbl setNeedsDisplay];
        
        
        NSString *tweetText = [tweet objectForKey:@"tweet"];
        NSString *source  = [tweet objectForKey:@"source"];
        source = source == nil ? @"" : source;
        NSString *date  = [self timeToString:[tweet objectForKey:@"date"]];
        
        BOOL isDM = ([tweet objectForKey:@"directMessage"] != nil);
        
        NSString *rtscreenName  = [tweet objectForKey:@"rtscreenName"];
        if(!isDM && rtscreenName != nil){
            NSMutableDictionary *selectedTwitterApp = [plugin.preferences objectForKey:@"SelectedTwitterApp"];
            NSString *UserViewUrl  = [selectedTwitterApp objectForKey:@"UserViewUrl"];            
            rtscreenName = [NSString stringWithFormat:@"Retweeted by <a href='%@%@'>%@</a>", UserViewUrl, rtscreenName, rtscreenName];
        }else{
            rtscreenName = @"";
        }
        NSString *html = [NSString stringWithFormat:@"<html><head><style>div{padding:10px;}#time{font-size:small;color:gray;}a{text-decoration:none;color:#3579db;font-weight:bold;}body{font:18px 'Helvetica Neue',Helvetica,sans-serif;}</style></head><body><div id='tweet'>%@</div><div id='time'>%@ &#9679; %@ <br/> %@</div></body></html>", [self parseTweetText:tweetText], source, date, rtscreenName];
        [self.webView loadHTMLString:html baseURL:[NSURL URLWithString:@""]];
    }    
    
}

-(void) switchToReadView
{
    WRITE_MODE = NO;
    [self.previewTextView resignFirstResponder];
    [self.view sendSubviewToBack:self.editView];
    [self.view bringSubviewToFront:self.readView];
	[self hideKeyboard];
}
-(void) switchToWriteView
{
    WRITE_MODE = YES;
    [self.view sendSubviewToBack:self.readView];
    [self.view bringSubviewToFront:self.editView];
    [self.previewTextView becomeFirstResponder];
	[self showKeyboard];

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
    
    BOOL isDM = ([self.previewTweet objectForKey:@"directMessage"] != nil);
    NSString* url = @"https://api.twitter.com/1/statuses/update.xml";
    NSMutableDictionary* params = nil;    
    if(isDM)
    {
        url = @"https://api.twitter.com/1/direct_messages/new.xml";
        params = [NSMutableDictionary dictionaryWithObjectsAndKeys:tweet, @"text", nil];
        NSString* name = [self.previewTweet objectForKey:@"screenName"];
        [params setValue:name forKey:@"screen_name"];
    }
    else if([tweet isEqualToString: RT_IDENTIFIER_TEXT])
    {
        if (NSString* id = [self.previewTweet objectForKey:@"id"])
        {
            params = [NSMutableDictionary dictionary];    
            url = [NSString stringWithFormat:@"https://api.twitter.com/1/statuses/retweet/%@.xml", id];
        }
    }
    else
    {
        params = [NSMutableDictionary dictionaryWithObjectsAndKeys:tweet, @"status", nil];
        if (NSString* id = [self.previewTweet objectForKey:@"id"])
            [params setValue:id forKey:@"in_reply_to_status_id"];
        
    }
    
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
    [self hideKeyboard]; 
}

-(void) dismissDetailTweet
{
	[self.webView resignFirstResponder];
	[self.plugin dismissPreview];
}


-(void) openButtonPressed
{
    NSString* id = [self.previewTweet objectForKey:@"id"];
    NSString* name = [self.previewTweet objectForKey:@"screenName"];
    BOOL isDM = ([self.previewTweet objectForKey:@"directMessage"] != nil);
    [self dismissDetailTweet];
    NSMutableDictionary *selectedTwitterApp = [plugin.preferences objectForKey:@"SelectedTwitterApp"];
    NSString *TweetViewUrl  = isDM ? [selectedTwitterApp objectForKey:@"MessageViewUrl"] : [selectedTwitterApp objectForKey:@"TweetViewUrl"];                       
    [self.plugin launchURL: [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", TweetViewUrl, isDM ? name : id]]]; 
    
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
    return [self doTweet:tweet isRetweet: NO];
}

-(UIView*) doTweet:(NSDictionary*) tweet isRetweet:(BOOL)isRetweet
{
	self.navigationItem.title = localize(@"Twitter");
	self.navigationItem.leftBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:localizeGlobal(@"Cancel") style:UIBarButtonItemStyleBordered target:self action:@selector(dismissTweet)] autorelease];
	self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:localizeGlobal(@"Send") style:UIBarButtonItemStyleDone target:self action:@selector(sendButtonPressed)] autorelease];
    
	self.previewTweet = tweet;
    
	if (self.isViewLoaded)
	{
        [self switchToWriteView];
        NSString *tweetText = [self.previewTweet objectForKey:@"tweet"];
		if (NSString* name = [self.previewTweet objectForKey:@"screenName"])
        {
            if(isRetweet)
            {
                self.previewTextView.text = [NSString stringWithFormat:@"RT @%@ %@", name, tweetText];
            }
            else
            {
                BOOL isDM = ([self.previewTweet objectForKey:@"directMessage"] != nil);
                if(isDM)
                {
                    self.previewTextView.text = @"";
                }
                else{
                    NSString *replyText = [self parseTweetTextForReply:tweetText];
                    self.previewTextView.text = [NSString stringWithFormat:@"@%@ %@", name, [tweetText isEqualToString:replyText] ? @"" : replyText];
                }
                
            }
        }
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
- (void)webViewDidStartLoad:(UIWebView *)webView
{
    [self.activity startAnimating];
}
- (void)webViewDidFinishLoad:(UIWebView *)webView
{
    [self.activity stopAnimating];        
}

- (BOOL)webView:(UIWebView*)webView shouldStartLoadWithRequest:(NSURLRequest*)request navigationType:(UIWebViewNavigationType)navigationType {
    
    NSURL *url = request.URL;
    if ([request.URL.scheme isEqualToString:@"litwitter"]){
        NSMutableDictionary *selectedTwitterApp = [plugin.preferences objectForKey:@"SelectedTwitterApp"];
        NSString *hashOrUser = [[url absoluteString] substringFromIndex: [@"litwitter://a?o=" length]];
        if([hashOrUser rangeOfString:@"@"].location == 0){
            NSString *UserViewUrl  = [selectedTwitterApp objectForKey:@"UserViewUrl"];            
            url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", UserViewUrl, [hashOrUser encodedURLParameterString]]];
        }else if([hashOrUser rangeOfString:@"#"].location == 0){
            NSString *HashSearchUrl  = [selectedTwitterApp objectForKey:@"HashSearchUrl"];            
            url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", HashSearchUrl, [hashOrUser encodedURLParameterString]]];
        }
    }
    [self.plugin launchURL: url];
	return NO;
    
}

-(UIView*) showDetailTweet:(NSDictionary*) tweet
{
	self.navigationItem.title = localize(@"Twitter");
	self.navigationItem.leftBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:localizeGlobal(@"Cancel") style:UIBarButtonItemStyleBordered target:self action:@selector(dismissDetailTweet)] autorelease];
    self.navigationItem.rightBarButtonItem = nil;
    
	self.previewTweet = tweet;
    
	if (self.isViewLoaded)
	{
        [self switchToReadView];
		[self fillDetailView:self.previewTweet];
    }
    self.previewController = [[[UINavigationController alloc] initWithRootViewController:self] autorelease];
    UINavigationBar* bar = self.previewController.navigationBar;
    bar.barStyle = UIBarStyleBlackOpaque;
    
    UIToolbar* toolbar = [self.previewController toolbar];
    toolbar.barStyle = UIBarStyleBlackOpaque;
    [self.previewController setToolbarHidden:NO];
    
    UIBarButtonItem *reply = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemReply target:self action:@selector(doReply)];
    UIBarButtonItem *flexspace = [[UIBarButtonItem alloc] initWithBarButtonSystemItem: UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    UIBarButtonItem *open = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(openButtonPressed)];
    UIBarButtonItem *retweet = nil;
    
    NSArray *buttons = nil;
    
    BOOL isDM = ([self.previewTweet objectForKey:@"directMessage"] != nil);
    if(isDM){
        
        buttons = [NSArray arrayWithObjects: reply, flexspace, open, nil];
        
    }else{
        UIImage* img = [UIImage li_imageWithContentsOfResolutionIndependentFile:[self.plugin.bundle pathForResource:@"LITwitterRetweet" ofType:@"png"]];
        retweet = [[UIBarButtonItem alloc] initWithImage:img style:UIBarButtonItemStylePlain target:self action:@selector(doRetweet)];
        buttons = [NSArray arrayWithObjects: reply,  flexspace, retweet, flexspace, open, nil];
    }
    [self setToolbarItems:buttons];
    [reply release];
    [open release];
    [flexspace release];            
    if(retweet != nil)
        [retweet release];
	return self.previewController.view;
}

- (void) doReply
{
    [self.previewController setToolbarHidden:YES];
	[self.plugin showPreview: [self showTweet:self.previewTweet]];
    [self switchToWriteView];
    
}
- (void) doRetweet
{
    BOOL useOldRT = NO;
	if (NSNumber* n = [self.plugin.preferences objectForKey:@"UseOldRT"])
		useOldRT = n.boolValue;
    if(useOldRT)
    {
        [self.previewController setToolbarHidden:YES];
        [self.plugin showPreview: [self doTweet:self.previewTweet isRetweet:YES]];
        [self switchToWriteView];
    }
    else
    {
        [self performSelectorInBackground:@selector(sendTweetInBackground:) withObject:RT_IDENTIFIER_TEXT];
        [self dismissDetailTweet];
    }
    
}

-(NSString *) extractUsersFrom:(NSString *) token tweetText:(NSString *)tweetText
{
    if(token == nil)
    {
        return @"";      
    }
    NSCharacterSet *user = [NSCharacterSet characterSetWithCharactersInString:@"@"];
    NSCharacterSet *ignoredPunctuationsAndChars = [NSCharacterSet characterSetWithCharactersInString:@"!,:;.?()[]{}/\\`'\"<>#@"] ;
    int index = NSNotFound;
    int endIndex = NSNotFound;
    NSString *nextToken = nil;
    if((index = [token rangeOfCharacterFromSet:user].location) != NSNotFound)
    {
        token = [token substringFromIndex: index];
        if((endIndex = [[token substringFromIndex:1] rangeOfCharacterFromSet:ignoredPunctuationsAndChars].location) != NSNotFound)
        {
            endIndex++;
            nextToken = [token substringFromIndex:endIndex];
            token = [token substringToIndex:endIndex];
        }
        if([tweetText rangeOfString:token options:NSCaseInsensitiveSearch].location == NSNotFound)
        {
            tweetText = [tweetText stringByAppendingString: token];
            tweetText = [tweetText stringByAppendingString: @" "];
        }
        tweetText = [tweetText stringByAppendingString: [self extractUsersFrom: nextToken tweetText: tweetText]];
        
    }
    return tweetText;
}


-(NSString *) detectHashAndUserLinksInToken:(NSString *) token formattedHtml: (NSString *)formattedHtml
{
    if(token == nil)
    {
        return [formattedHtml stringByAppendingString: @" "];      
    }
    NSCharacterSet *hashOrUser = [NSCharacterSet characterSetWithCharactersInString:@"#@"];
    NSCharacterSet *ignoredPunctuationsAndChars = [NSCharacterSet characterSetWithCharactersInString:@"!,:;.?()[]{}/\\`'\"<>#@"] ;
    NSString *linkFormat = @"<a href='litwitter://a?o=%@'>%@</a>";
    
    int index = NSNotFound;
    int endIndex = NSNotFound;
    NSString *nextToken = nil;
    if((index = [token rangeOfCharacterFromSet:hashOrUser].location) != NSNotFound)
    {
        formattedHtml = [formattedHtml stringByAppendingString: [token substringToIndex:index]];
        token = [token substringFromIndex: index];
        if((endIndex = [[token substringFromIndex:1] rangeOfCharacterFromSet:ignoredPunctuationsAndChars].location) != NSNotFound)
        {
            endIndex++;
            nextToken = [token substringFromIndex:endIndex];
            token = [token substringToIndex:endIndex];
        }
        formattedHtml = [formattedHtml stringByAppendingString: [NSString stringWithFormat: linkFormat, token, token]];
        formattedHtml = [self processToken: nextToken formattedHtml: formattedHtml];
        
    }else{
        formattedHtml = [formattedHtml stringByAppendingString: [NSString stringWithFormat: @"%@ ", token]];      
    }
    return formattedHtml;
}

-(NSString *) parseTweetTextForReply:(NSString *) text
{
    NSString *replyText = @"";
    if(NSClassFromString(@"NSRegularExpression") != nil)
    {
        NSError *error = NULL;
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"[^@]*(@[a-zA-Z0-9_\\-]+)+[^@]*"
                                                                               options:NSRegularExpressionCaseInsensitive
                                                                                 error:&error];
        replyText = [regex stringByReplacingMatchesInString:text
                                                        options:0
                                                          range:NSMakeRange(0, [text length])
                                                   withTemplate:@"$1 "];
    }
    return replyText; 
}


-(NSString *) parseTweetText:(NSString *) text
{
    NSString *formattedHtml = @"";
    if(NSClassFromString(@"NSRegularExpression") != nil)
    {
        NSError *error = NULL;
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"([#@][a-zA-Z0-9_\\-]+)"
                                                                               options:NSRegularExpressionCaseInsensitive
                                                                                 error:&error];
        formattedHtml = [regex stringByReplacingMatchesInString:text
                                                        options:0
                                                          range:NSMakeRange(0, [text length])
                                                   withTemplate:@"<a href='litwitter://a?o=$1'>$1</a>"];
    }
    else
    {        
        NSArray *words = [text componentsSeparatedByString: @" "];
        for(int i = 0; i < [words count]; i++)
        {
            NSString *token = [words objectAtIndex:i];
            formattedHtml = [self detectHashAndUserLinksInToken: token formattedHtml: formattedHtml];
        }
    }
    return formattedHtml; 
    
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
		BOOL showPreview = YES;
		if (NSNumber* n = [self.plugin.preferences objectForKey:@"ShowPreview"])
			showPreview = n.boolValue;
        
		if (showPreview){
            
            return [self showDetailTweet:[self.tweets objectAtIndex:row]];
        }
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
		[elementName isEqualToString:@"screen_name"] ||
        [elementName isEqualToString:@"source"])
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
    else if ([elementName isEqualToString:@"source"])
	{
		[self.currentTweet setValue:self.xml forKey:@"source"];
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
        else if([self.currentTweet objectForKey:@"rtname"] == nil)
        {
            [self.currentTweet setValue:self.xml forKey:@"rtname"];    
        }
	}
	else if ([elementName isEqualToString:@"screen_name"])
	{
		if ([self.currentTweet objectForKey:@"screenName"] == nil)
		{
			[self.currentTweet setValue:self.xml forKey:@"screenName"];
		}
        else if([self.currentTweet objectForKey:@"rtscreenName"] == nil)
        {
            [self.currentTweet setValue:self.xml forKey:@"rtscreenName"];    
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
-(NSString *) timeToString: (NSNumber *) dateNum
{
    NSString *timeString = @"";
    int diff = 0 - [[NSDate dateWithTimeIntervalSince1970:dateNum.doubleValue] timeIntervalSinceNow];
    if (diff > 86400)
    {
        int n = (int)(diff / 86400);
        timeString = (n == 1 ? @"1 day ago" : [NSString stringWithFormat:localize(@"%d days ago"), n]);
    }
    else if (diff > 3600)
    {
        int n = (int)(diff / 3600);
        if (diff % 3600 > 1800)
            n++;
        
        timeString = (n == 1 ? @"about 1 hour ago" : [NSString stringWithFormat:localize(@"about %d hours ago"), n]);
    }
    else if (diff > 60)
    {
        int n = (int)(diff / 60);
        if (diff % 60 > 30)
            n++;
        
        timeString = (n == 1 ? @"1 minute ago" : [NSString stringWithFormat:localize(@"%d minutes ago"), n]);
    }
    else
    {
        timeString = (diff == 1 ? @"1 second ago" : [NSString stringWithFormat:localize(@"%d seconds ago"), diff]);
    }
    
    return timeString;
    
}
- (void)segmentAction:(id)sender
{
	int selected = [sender selectedSegmentIndex];
	if (selectedIndex == selected)
		return;
    
	switch(selected)
	{
        case 0:
            [self switchToHomeline];
            break;
        case 1:
            [self switchToMentions];
            break;
        case 2:
            [self switchToMessages];
            break;
        case 3:
	        [self showNewTweet];
	        [sender setSelectedSegmentIndex:selectedIndex];
            return;
    }
    
    selectedIndex = selected;    
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
                
                //!TODO localized labels
                NSArray *segmentTextContent = [NSArray arrayWithObjects: @"Timeline", @"Mentions", @"Messages", @"Compose",  nil];
                
                UISegmentedControl *segments = [[[UISegmentedControl alloc] initWithItems:segmentTextContent] autorelease];
                segments.frame = CGRectMake(-5, 0, tableView.frame.size.width + 10, 24);
                segments.tag = 43443;
                segments.segmentedControlStyle = UISegmentedControlStyleBezeled;
                segments.selectedSegmentIndex = selectedIndex;
                segments.tintColor = [UIColor clearColor];
                [segments addTarget:self action:@selector(segmentAction:) forControlEvents:UIControlEventValueChanged];
                segments.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                [container addSubview:segments];
			}
            
            UISegmentedControl *segments = [cell viewWithTag:43443];
            segments.selectedSegmentIndex = selectedIndex;
            
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
    
	if (row < self.tweets.count )
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
        v.time = [self timeToString:dateNum];
	}
	
	[v setNeedsDisplay];
	return cell;
    
}
/*
 MSHook(void, setDelegate, id self, SEL sel, id delegate)
 {
 if (previewTextView)
 [previewTextView becomeFirstResponder];
 else
 _setDelegate(self, sel, delegate);
 
 }
 
 
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
    self.mentions = [NSMutableArray arrayWithCapacity:10];
    self.homeline = [NSMutableArray arrayWithCapacity:10];
    self.directMessages = [NSMutableArray arrayWithCapacity:10];
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
    [center addObserver:self selector:@selector(screenUndimmed:) name:LIUndimScreenNotification object:nil];
    
    
    //	Class $UIKeyboardImpl = objc_getClass("UIKeyboardImpl");
    //	Hook(UIKeyboardImpl, setDelegate:, setDelegate);
    
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

-(BOOL) loadTweets:(NSString*) url parameters:(NSDictionary*) parameters
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
		return NO;
	}
    
	NSString* header = [auth OAuthorizationHeader:request.URL method:@"GET" body:nil];
	[request setValue:header forHTTPHeaderField:@"Authorization"];
    NSError *anError = nil;
	NSData* data = [NSURLConnection sendSynchronousRequest:request returningResponse:NULL error:&anError];
    
    if(data == nil)
    {
        //        if(error != nil){ //!TODO Better error handling like ReqTimedOut out or host unreachable etc.
        return NO;
        //        }
    }
    
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
    return YES;
}

-(void) updateTweetsInView:(NSMutableArray*) array
{
	self.tweets = array;
	[self.plugin updateView:[NSDictionary dictionaryWithObjectsAndKeys:self.tweets, @"tweets", nil]];
}

-(void) switchToHomeline
{
	[self updateTweetsInView:self.homeline];
}

-(void) switchToMentions
{
	[self updateTweetsInView:self.mentions];
}

-(void) switchToMessages
{
	[self updateTweetsInView:self.directMessages];
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
    //	if (NSNumber* n = [self.plugin.preferences objectForKey:@"ShowFriends"])
    //		showFriends = n.boolValue;
    
	if (showFriends)
	{
		self.type = @"friend";
		if([self loadTweets:@"https://api.twitter.com/statuses/home_timeline.xml" parameters:[NSDictionary dictionaryWithObjectsAndKeys:[NSString stringWithFormat:@"%d", count+1], @"count", nil]])
        {
            self.homeline = [self.tempTweets.allValues sortedArrayUsingFunction:sortByDate context:nil];
            [self.tempTweets removeAllObjects];
            self.currentTweet = nil;
        }
	}
    
	BOOL showMentions = true;
    //	if (NSNumber* n = [self.plugin.preferences objectForKey:@"ShowMentions"])
    //		showMentions = n.boolValue;
    
	if (showMentions)
	{
		self.type = @"mention";
        if([self loadTweets:@"https://api.twitter.com/statuses/mentions.xml" parameters:[NSDictionary dictionaryWithObjectsAndKeys:[NSString stringWithFormat:@"%d", count+1], @"count", nil]])
        {
            self.mentions = [self.tempTweets.allValues sortedArrayUsingFunction:sortByDate context:nil];
            [self.tempTweets removeAllObjects];
            self.currentTweet = nil;
        }
	}
    
	BOOL showDMs = true;
    //	if (NSNumber* n = [self.plugin.preferences objectForKey:@"ShowDirectMessages"])
    //		showDMs = n.boolValue;
    
	if (showDMs)
	{
		self.type = @"directMessage";
		if([self loadTweets:@"https://api.twitter.com/1/direct_messages.xml" parameters:[NSDictionary dictionaryWithObjectsAndKeys:[NSString stringWithFormat:@"%d", count+1], @"count", nil]])
        {
            self.directMessages = [self.tempTweets.allValues sortedArrayUsingFunction:sortByDate context:nil];
            [self.tempTweets removeAllObjects];
            self.currentTweet = nil;
        }
	}
    
    if(selectedIndex == 0)
    {
    	[self updateTweetsInView:self.homeline];
    }
    else if(selectedIndex == 1)
    {
    	[self updateTweetsInView:self.mentions];
    }
    else if(selectedIndex == 2)
    {
    	[self updateTweetsInView:self.directMessages];
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
//Is there screen dim/screen lock notificaion as well?
- (void) screenUndimmed:(NSNotification*) notif
{
    if(WRITE_MODE)
    {
        WRITE_MODE = NO;
        [self.previewTextView resignFirstResponder];
        [self hideKeyboard];
    }
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