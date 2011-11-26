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
#import "JSONKit/JSONKit.h"

@interface UIScreen (LIAdditions)

- (float)scale;

@end

Class $SBTelephonyManager = objc_getClass("SBTelephonyManager");

#define Hook(cls, sel, imp) \
_ ## imp = MSHookMessage($ ## cls, @selector(sel), &$ ## imp)

@interface TwitterAuthController : PSDetailController <UIWebViewDelegate, UIAlertViewDelegate>

@property(nonatomic, retain) UIWebView *webView;
@property(nonatomic, retain) UIActivityIndicatorView *activity;
@property(retain) TwitterAuth *auth;

@end

@implementation TwitterAuthController

@synthesize webView, activity;
@synthesize auth;

- (void)loadURL:(NSURL *)url {
    self.activity = [[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite] autorelease];

    UIView *view = [self view];
    view.autoresizingMask = (UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight);
    view.autoresizesSubviews = YES;

    self.webView = [[[UIWebView alloc] initWithFrame:view.bounds] autorelease];
    self.webView.autoresizesSubviews = YES;
    self.webView.autoresizingMask = (UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth);
    self.webView.scalesPageToFit = YES;
    self.webView.delegate = self;
    [view addSubview:self.webView];

    [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
}

- (void)initAuth {
    if (self.auth == nil) {
        self.auth = [[[TwitterAuth alloc] init] autorelease];
        if ([self.auth requestTwitterToken])
            [self loadURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://api.twitter.com/oauth/authorize?oauth_token=%@", self.auth.oauth_token]]];
        else
            NSLog(@"LI:Twitter: Token request failed!");
    }
}

- (void)viewWillBecomeVisible:(id)spec {
    [super viewWillBecomeVisible:spec];
    [self initAuth];
}

- (void)viewWillAppear:(BOOL)a {
    [super viewWillAppear:a];
    [self.view bringSubviewToFront:self.webView];
    [self initAuth];
}

- (void)setBarButton:(UIBarButtonItem *)button {
    PSRootController *root = self.rootController;
    UINavigationBar *bar = root.navigationBar;
    UINavigationItem *item = bar.topItem;
    item.rightBarButtonItem = button;
}

- (void)startLoad:(UIWebView *)wv {
    CGRect r = self.activity.frame;
    r.size.width += 5;
    UIView *v = [[[UIView alloc] initWithFrame:r] autorelease];
    v.backgroundColor = [UIColor clearColor];
    [v addSubview:self.activity];
    [self.activity startAnimating];
    UIBarButtonItem *button = [[[UIBarButtonItem alloc] initWithCustomView:v] autorelease];
    [self setBarButton:button];

    UIApplication *app = [UIApplication sharedApplication];
    app.networkActivityIndicatorVisible = YES;
}

- (BOOL)webView:(UIWebView *)wView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType {
    if ([request.URL.scheme isEqualToString:@"http"]) {
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

    [self startLoad:wView];
    return YES;
}

- (void)webViewDidFinishLoad:(UIWebView *)wv {
    [self.activity stopAnimating];
    [self setBarButton:[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:wv action:@selector(reload)] autorelease]];

    UIApplication *app = [UIApplication sharedApplication];
    app.networkActivityIndicatorVisible = NO;
}

- (id)navigationTitle {
    return @"Authentication";
}

@end

@interface UIProgressIndicator : UIView

+ (CGSize)defaultSizeForStyle:(int)size;

- (void)setStyle:(int)style;

@end

extern "C" CFStringRef UIDateFormatStringForFormatType(CFStringRef type);

#define localize(str) \
[self.plugin.bundle localizedStringForKey:str value:str table:nil]

#define localizeSpec(str) \
[self.bundle localizedStringForKey:str value:str table:nil]

#define localizeGlobal(str) \
[self.plugin.globalBundle localizedStringForKey:str value:str table:nil]

static NSString *TWITTER_SERVICE = @"com.ashman.lockinfo.TwitterPlugin";

static void prepareObject(id obj1, NSDictionary* imageCache) {

    NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
    formatter.locale = [[[NSLocale alloc] initWithLocaleIdentifier:@"en_US"] autorelease];
    formatter.dateFormat = @"EEE MMM dd HH:mm:ss Z yyyy";

    if([obj1 objectForKey:@"sender"] != nil){
        [obj1 setValue:[obj1 objectForKey:@"sender"] forKey:@"user"];    
    } 
    if([obj1 objectForKey:@"retweeted_status"] != nil && [obj1 objectForKey:@"retweeted_by_user"] == nil){
        
        [obj1 setValue:[obj1 valueForKeyPath:@"user.name"] forKey:@"retweeted_by_user"];
        
        NSDictionary *origTweet = [obj1 valueForKeyPath:@"retweeted_status"];
        [obj1 setValue:[origTweet objectForKey:@"user"] forKey:@"user"];
        [obj1 setValue:[origTweet objectForKey:@"id_str"] forKey:@"id_str"];
        [obj1 setValue:[origTweet objectForKey:@"text"] forKey:@"text"];
        [obj1 setValue:[origTweet objectForKey:@"source"] forKey:@"source"];
        
    }
    if (NSString *url = [obj1 valueForKeyPath:@"user.profile_image_url"]) {
        if([imageCache objectForKey: url] == nil){
            if([imageCache count] >= 50){ //keep only 50 images max in this cache.
                [imageCache removeObjectForKey:[[imageCache allKeys] lastObject]];
            }
            [imageCache setValue:[[[UIImage alloc] initWithData:[NSData dataWithContentsOfURL:[NSURL URLWithString:url]]] autorelease] forKey:url];
        }
    }
    if ([obj1 objectForKey:@"created_at"] != nil) {
        NSDate *d = [formatter dateFromString:[obj1 objectForKey:@"created_at"]];
        NSTimeInterval time = [d timeIntervalSince1970];
        [obj1 setValue:[NSNumber numberWithDouble:time] forKey:@"date"];
        [obj1 removeObjectForKey:@"created_at"];
    }
}
static NSInteger prepareAndSortByDate(id obj1, id obj2, void *context) {
    NSMutableDictionary* imageCache = (NSMutableDictionary *) context;
    
    prepareObject(obj1, imageCache);
    prepareObject(obj2, imageCache);
    
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

@property(nonatomic, retain) NSString *name;
@property(nonatomic, retain) NSString *tweet;
@property(nonatomic, retain) NSString *time;
@property(nonatomic, retain) UIImage *image;
@property(nonatomic) BOOL directMessage;
@property(nonatomic, retain) LITheme *theme;

@end

static UIImage *directMessageIcon;

@implementation TweetView

@synthesize name, time, image, theme, tweet, directMessage;

- (void)setFrame:(CGRect)r {
    [super setFrame:r];
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    CGRect r = self.superview.bounds;

    NSString *theName = self.name;
    CGSize nameSize = [theName sizeWithFont:self.theme.summaryStyle.font];
    CGRect imageRect = CGRectMake(5, 5, (int) (nameSize.height * 1.4), (int) (nameSize.height * 1.4));

    NSString *padding = stringPaddingWithFont(self.theme.detailStyle.font, imageRect.origin.x + imageRect.size.width + 4);
    CGSize paddingSize = [padding sizeWithFont:self.theme.detailStyle.font];

    NSString *text = [padding stringByAppendingString:self.tweet];

    [theName drawInRect:CGRectMake(5 + paddingSize.width, 0, nameSize.width, nameSize.height) withLIStyle:self.theme.summaryStyle lineBreakMode:UILineBreakModeTailTruncation];

    LIStyle *timeStyle = [self.theme.detailStyle copy];
    timeStyle.font = [UIFont systemFontOfSize:self.theme.detailStyle.font.pointSize];
    CGSize timeSize = [self.time sizeWithFont:timeStyle.font];
    [self.time drawInRect:CGRectMake(r.size.width - timeSize.width - 5, nameSize.height - timeSize.height, timeSize.width, timeSize.height) withLIStyle:timeStyle lineBreakMode:UILineBreakModeClip alignment:UITextAlignmentRight];
    [timeStyle release];

    CGSize s = [text sizeWithFont:self.theme.detailStyle.font constrainedToSize:CGSizeMake(r.size.width - 10, 4000) lineBreakMode:UILineBreakModeWordWrap];
    [text drawInRect:CGRectMake(5, nameSize.height, s.width, s.height) withLIStyle:self.theme.detailStyle lineBreakMode:UILineBreakModeWordWrap];

    [self.image drawInRoundedRect:imageRect withRadius:3];

    if (self.directMessage) {
        CGRect iconRect = CGRectMake(imageRect.origin.x + imageRect.size.width + 3 - directMessageIcon.size.width, imageRect.origin.y + imageRect.size.height + 3 - directMessageIcon.size.height, directMessageIcon.size.width, directMessageIcon.size.height);
        [directMessageIcon drawInRect:iconRect];
    }
}

@end

@interface UIKeyboardImpl : UIView
@property(nonatomic, retain) id delegate;
@end

@interface UIKeyboard : UIView

+ (UIKeyboard *)activeKeyboard;

+ (void)initImplementationNow;

+ (CGSize)defaultSize;

@end


static NSNumber *YES_VALUE = [NSNumber numberWithBool:YES];
static int selectedIndex = 0;
static int tapCount = 0;
static BOOL WRITE_MODE = YES;
static NSString *const RT_IDENTIFIER_TEXT = @"_li__tp___rt____id_____";
static int const TYPE_STATUS = 0;
static int const TYPE_PROFILE = 1;
static int const TYPE_DIRECT_MESSAGE = 2;
static int const TYPE_SEARCH = 3;

#define UIColorFromRGB(rgbValue) [UIColor colorWithRed:((float)((rgbValue & 0xFF0000) >> 16))/255.0 green:((float)((rgbValue & 0xFF00) >> 8))/255.0 blue:((float)(rgbValue & 0xFF))/255.0 alpha:1.0]

@interface TwitterPlugin : UIViewController <LIPluginController, LITableViewDelegate, UITableViewDataSource, UITextViewDelegate, LIPreviewDelegate, UIWebViewDelegate, NSXMLParserDelegate> {
    NSTimeInterval nextUpdate;
    NSDateFormatter *formatter;
    NSConditionLock *lock;
}

@property(nonatomic, retain) LIPlugin *plugin;
@property(retain) NSArray *tweets;
@property(retain) NSMutableArray *timeline;
@property(retain) NSMutableArray *mentions;
@property(retain) NSMutableArray *directMessages;
@property(retain) NSMutableDictionary *imageCache;
@property(nonatomic, retain) UINavigationController *previewController;
@property(nonatomic, retain) UILabel *countLabel;

@property(retain) NSMutableArray *tempTweets;
@property(retain) NSMutableDictionary *currentTweet;
@property(retain) NSMutableString *xml;
@property(retain) NSString *type;
@property(retain) NSArray *toolbarButtons;


@property(nonatomic, retain) UIView *newTweetView;

// preview stuff
@property(nonatomic, retain) NSDictionary *previewTweet;
@property(nonatomic, retain) UITextView *previewTextView;
@property(nonatomic, retain) UIWebView *webView;

@property(nonatomic, retain) UIView *editView;
@property(nonatomic, retain) UIView *readView;
@property(nonatomic, retain) UIActivityIndicatorView *activity;


@end

@implementation TwitterPlugin

@synthesize tweets, timeline, mentions, directMessages, tempTweets, xml, plugin, imageCache, type, currentTweet, previewController, countLabel;

@synthesize previewTweet, previewTextView, newTweetView, webView, editView, readView, activity, toolbarButtons;

- (void)setCount:(int)count {
    self.countLabel.text = [[NSNumber numberWithInt:count] stringValue];
}
/*
 - (BOOL)textViewShouldBeginEditing:(UITextView *)textView{
 return YES;
 }
 */
- (void)showKeyboard {
    if ([self.plugin respondsToSelector:@selector(showKeyboard:)]) {
        [self.plugin showKeyboard:self.previewTextView];
    }
    else {
        if (Class peripheral = objc_getClass("UIPeripheralHost")) {
            [[peripheral sharedInstance] setAutomaticAppearanceEnabled:YES];
            [[peripheral sharedInstance] orderInAutomatic];
        }
        else {
            [[UIKeyboard automaticKeyboard] orderInWithAnimation:YES];
        }
    }
}

- (void)hideKeyboard {
    if ([self.plugin respondsToSelector:@selector(hideKeyboard)]) {
        [self.plugin hideKeyboard];
    }
    else {
        if (Class peripheral = objc_getClass("UIPeripheralHost")) {
            [[peripheral sharedInstance] orderOutAutomatic];
            [[peripheral sharedInstance] setAutomaticAppearanceEnabled:NO];
        }
        else {
            [[UIKeyboard automaticKeyboard] orderOutWithAnimation:YES];
        }
    }
}

- (void)previewWillDismiss:(LIPreview *)preview {
    if (![self.plugin respondsToSelector:@selector(hideKeyboard)]) {
        [self.previewTextView resignFirstResponder];
        [self hideKeyboard];
    }
}

- (void)previewDidShow:(LIPreview *)preview {
    if (WRITE_MODE) {
        [self.previewTextView becomeFirstResponder];
        [self showKeyboard];
    }
    else {
        [self.previewTextView resignFirstResponder];
        [self hideKeyboard];
    }
}

- (NSString *)timeToString:(NSNumber *)dateNum {
    NSString *timeString = @"";
    int diff = 0 - (int) [[NSDate dateWithTimeIntervalSince1970:dateNum.doubleValue] timeIntervalSinceNow];
    if (diff > 86400) {
        int n = (int) (diff / 86400);
        timeString = (n == 1 ? @"1 day ago" : [NSString stringWithFormat:localize(@"%d days ago"), n]);
    }
    else if (diff > 3600) {
        int n = (int) (diff / 3600);
        if (diff % 3600 > 1800)
            n++;

        timeString = (n == 1 ? @"about 1 hour ago" : [NSString stringWithFormat:localize(@"about %d hours ago"), n]);
    }
    else if (diff > 60) {
        int n = (int) (diff / 60);
        if (diff % 60 > 30)
            n++;

        timeString = (n == 1 ? @"1 minute ago" : [NSString stringWithFormat:localize(@"%d minutes ago"), n]);
    }
    else {
        timeString = (diff == 1 ? @"1 second ago" : [NSString stringWithFormat:localize(@"%d seconds ago"), diff]);
    }

    return timeString;

}

- (NSString *)buildURLStringForTwitterApp:(int)urlType  param:(NSString *)param {
    NSMutableDictionary *selectedTwitterApp = [self.plugin.preferences objectForKey:@"SelectedTwitterApp"];
    NSString *targetUrl = nil;
    switch (urlType) {
        case TYPE_STATUS:
            targetUrl = [selectedTwitterApp objectForKey:@"TweetViewUrl"];
            break;
        case TYPE_PROFILE:
            targetUrl = [selectedTwitterApp objectForKey:@"UserViewUrl"];
            break;
        case TYPE_DIRECT_MESSAGE:
            targetUrl = [selectedTwitterApp objectForKey:@"MessageViewUrl"];
            break;
        case TYPE_SEARCH:
            targetUrl = [selectedTwitterApp objectForKey:@"HashSearchUrl"];
            break;
        default:
            break;
    }
    return [NSString stringWithFormat:@"%@%@", targetUrl, [param encodedURLParameterString]];
}

- (NSString *)detectHashAndUserLinksInToken:(NSString *)token formattedHtml:(NSString *)formattedHtml {
    if (token == nil) {
        return [formattedHtml stringByAppendingString:@" "];
    }
    NSCharacterSet *hashOrUser = [NSCharacterSet characterSetWithCharactersInString:@"#@"];
    NSCharacterSet *ignoredPunctuationsAndChars = [NSCharacterSet characterSetWithCharactersInString:@"!,:;.?()[]{}/\\`'\"<>#@"];
    NSString *linkFormat = @"<a href='litwitter://a?o=%@'>%@</a>";

    int index = NSNotFound;
    int endIndex = NSNotFound;
    NSString *nextToken = nil;
    if ((index = [token rangeOfCharacterFromSet:hashOrUser].location) != NSNotFound) {
        formattedHtml = [formattedHtml stringByAppendingString:[token substringToIndex:index]];
        token = [token substringFromIndex:index];
        if ((endIndex = [[token substringFromIndex:1] rangeOfCharacterFromSet:ignoredPunctuationsAndChars].location) != NSNotFound) {
            endIndex++;
            nextToken = [token substringFromIndex:endIndex];
            token = [token substringToIndex:endIndex];
        }
        formattedHtml = [formattedHtml stringByAppendingString:[NSString stringWithFormat:linkFormat, token, token]];
        formattedHtml = [self detectHashAndUserLinksInToken:nextToken formattedHtml:formattedHtml];

    } else {
        formattedHtml = [formattedHtml stringByAppendingString:[NSString stringWithFormat:@"%@ ", token]];
    }
    return formattedHtml;
}

- (NSString *)parseTweetText:(NSString *)text {
    NSString *formattedHtml = @"";
    if (NSClassFromString(@"NSRegularExpression") != nil) {
        NSError *error = NULL;
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"([#@][a-zA-Z0-9_\\-]+)"
                                                                               options:NSRegularExpressionCaseInsensitive
                                                                                 error:&error];
        formattedHtml = [regex stringByReplacingMatchesInString:text
                                                        options:0
                                                          range:NSMakeRange(0, [text length])
                                                   withTemplate:@"<a href='litwitter://a?o=$1'>$1</a>"];
    }
    else {
        NSArray *words = [text componentsSeparatedByString:@" "];
        for (unsigned int i = 0; i < [words count]; i++) {
            NSString *token = [words objectAtIndex:i];
            formattedHtml = [self detectHashAndUserLinksInToken:token formattedHtml:formattedHtml];
        }
    }
    return formattedHtml;

}

- (void)fillDetailView:(NSDictionary *)tweet {

    if (NSString *name = [tweet valueForKeyPath:@"user.name"]) {
        NSString *screenName = [NSString stringWithFormat:@"@%@", [tweet valueForKeyPath:@"user.screen_name"]];

        NSString *imageUrl = [tweet valueForKeyPath:@"user.profile_image_url"];

        UIImageView *profImg = (UIImageView *) [self.readView viewWithTag:100]; //img view
        [profImg setImage:[self.imageCache objectForKey:imageUrl]];
        [profImg setNeedsDisplay];

        UILabel *nameLbl = (UILabel *) [self.readView viewWithTag:101]; //name lbl
        nameLbl.text = name;
        [nameLbl setNeedsDisplay];

        UILabel *screenLbl = (UILabel *) [self.readView viewWithTag:102]; //screenname lbl
        screenLbl.text = screenName;
        [screenLbl setNeedsDisplay];


        NSString *tweetText = [tweet objectForKey:@"text"];
        NSString *source = [tweet objectForKey:@"source"];
        source = source == nil ? @"" : source;
        NSString *date = [self timeToString:[tweet objectForKey:@"date"]];

        BOOL isDM = ([tweet objectForKey:@"sender_id"] != nil);

        NSString *rtscreenName = [tweet objectForKey:@"retweeted_by_user"];
        if (!isDM && rtscreenName != nil) {
            rtscreenName = [NSString stringWithFormat:@"Retweeted by <a href='%@'>%@</a>",
                                                      [self buildURLStringForTwitterApp:TYPE_PROFILE param:rtscreenName], rtscreenName];
        } else {
            rtscreenName = @"";
        }
        NSString *html = [NSString stringWithFormat:@"<html><head><style>div{padding:10px;}#time{font-size:small;color:gray;}a{text-decoration:none;color:#3579db;font-weight:bold;}body{font:18px 'Helvetica Neue',Helvetica,sans-serif;}</style></head><body><div id='tweet'>%@</div><div id='time'>%@ &#9679; %@ <br/> %@</div></body></html>",
                                                    [self parseTweetText:tweetText], source, date, rtscreenName];
        [self.webView loadHTMLString:html baseURL:[NSURL URLWithString:@""]];
    }

}

- (void)switchToReadView {
    WRITE_MODE = NO;
    [self.previewTextView resignFirstResponder];
    [self.view sendSubviewToBack:self.editView];
    [self.view bringSubviewToFront:self.readView];
    [self hideKeyboard];
}

- (void)switchToWriteView {
    WRITE_MODE = YES;
    [self.view sendSubviewToBack:self.readView];
    [self.view bringSubviewToFront:self.editView];
    [self.previewTextView becomeFirstResponder];
    [self showKeyboard];

}

- (void)loadView {

    UIView *v = [[[UIView alloc] initWithFrame:[[UIScreen mainScreen] applicationFrame]] autorelease];
    v.backgroundColor = [UIColor blackColor];

    UIView *eView = [[[UIView alloc] initWithFrame:v.bounds] autorelease];
    eView.backgroundColor = [UIColor blackColor];

    UITextView *tv = [[[UITextView alloc] initWithFrame:v.bounds] autorelease];
    tv.backgroundColor = [UIColor blackColor];
    tv.editable = YES;
    tv.userInteractionEnabled = YES;
    tv.keyboardAppearance = UIKeyboardAppearanceAlert;
    tv.font = [UIFont systemFontOfSize:20];
    tv.textColor = [UIColor whiteColor];
    tv.delegate = self;
    [eView addSubview:tv];
    self.previewTextView = tv;

    UILabel *countLbl = [[[UILabel alloc] initWithFrame:CGRectMake(v.frame.size.width - 60, v.frame.size.height - [UIKeyboard defaultSize].height - 80, 60, 30)] autorelease];
    countLbl.backgroundColor = [UIColor clearColor];
    countLbl.font = [UIFont boldSystemFontOfSize:24];
    countLbl.textColor = [UIColor whiteColor];
    countLbl.textAlignment = UITextAlignmentCenter;
    [eView addSubview:countLbl];
    self.countLabel = countLbl;

    UIView *rView = [[[UIView alloc] initWithFrame:v.bounds] autorelease];
    rView.backgroundColor = UIColorFromRGB(0xC5CCd4);

    UIView *header = [[[UIView alloc] initWithFrame:v.bounds] autorelease];
    UITapGestureRecognizer *tapGesture =
            [[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openProfileInSelectedTwitterApp)] autorelease];
    [header addGestureRecognizer:tapGesture];


    UIImageView *profImg = [[[UIImageView alloc] initWithImage:[self.imageCache objectForKey:@""]] autorelease];
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
    [header addSubview:profImg];

    UILabel *nameLbl = [[[UILabel alloc] initWithFrame:CGRectMake(70, 10, 250, 48)] autorelease];
    nameLbl.font = [UIFont boldSystemFontOfSize:18];
    nameLbl.backgroundColor = [UIColor clearColor];
    nameLbl.textColor = [UIColor blackColor];
    nameLbl.textAlignment = UITextAlignmentLeft;
    nameLbl.shadowColor = UIColorFromRGB(0xFFFFFF);
    nameLbl.shadowOffset = CGSizeMake(0, 1.0);
    nameLbl.lineBreakMode = UILineBreakModeTailTruncation;
    nameLbl.tag = 101;
    [header addSubview:nameLbl];

    UILabel *screenLbl = [[[UILabel alloc] initWithFrame:CGRectMake(70, 30, 250, 48)] autorelease];
    screenLbl.font = [UIFont systemFontOfSize:14];
    screenLbl.backgroundColor = [UIColor clearColor];
    screenLbl.textColor = [UIColor blackColor];
    screenLbl.textAlignment = UITextAlignmentLeft;
    screenLbl.shadowColor = UIColorFromRGB(0xFFFFFF);
    screenLbl.shadowOffset = CGSizeMake(0, 1.0);
    screenLbl.lineBreakMode = UILineBreakModeTailTruncation;
    screenLbl.tag = 102;
    [header addSubview:screenLbl];
    [rView addSubview:header];

    UIWebView *wView = [[[UIWebView alloc] initWithFrame:CGRectMake(-1, 75, v.frame.size.width + 1, v.frame.size.height - 75)] autorelease];
    wView.delegate = self;
    wView.dataDetectorTypes = (UIDataDetectorTypeLink | UIDataDetectorTypePhoneNumber);
    layer = [wView layer];
    layer.masksToBounds = NO;
    layer.shadowColor = [UIColorFromRGB(0x999999) CGColor];
    layer.shadowOffset = CGSizeMake(0, -4);
    layer.shadowOpacity = 0.2;
    layer.shadowRadius = 10;
    layer.borderWidth = 1.0;
    layer.borderColor = [UIColorFromRGB(0X999999) CGColor];

    [rView addSubview:wView];
    self.activity = [[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray] autorelease];
    self.activity.center = CGPointMake(rView.frame.size.width / 2, 90.0);
    self.activity.hidesWhenStopped = YES;
    [rView addSubview:self.activity];

    self.webView = wView;

    self.editView = eView;
    self.readView = rView;

    [self setCount:140 - tv.text.length];
    [v addSubview:rView];
    [v addSubview:eView];
    self.view = v;

    if ([self.previewTweet objectForKey:@"id_str"] != nil) {
        [self fillDetailView:self.previewTweet];
        [self switchToReadView];
    } else {
        [self switchToWriteView];
    }

}

- (BOOL)keyboardInputShouldDelete:(UITextView *)input {
    [self setCount:140 - input.text.length];
    return YES;
}

- (void)sendTweet:(NSString *)tweet {
    UIProgressIndicator *ind = [[[UIProgressIndicator alloc] initWithFrame:CGRectMake(0, 0, 14, 14)] autorelease];
    ind.tag = 575933;
    ind.center = self.newTweetView.center;
    [ind setStyle:1];
    [ind startAnimation];

    self.newTweetView.hidden = YES;
    [self.newTweetView.superview addSubview:ind];

    [self performSelectorInBackground:@selector(sendTweetInBackground:) withObject:tweet];
}


- (void)sendTweetInBackground:(NSString *)tweet {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    BOOL isDM = ([self.previewTweet objectForKey:@"sender_id"] != nil);
    NSString *url = @"https://api.twitter.com/1/statuses/update.xml";
    NSMutableDictionary *params = nil;
    if (isDM) {
        url = @"https://api.twitter.com/1/direct_messages/new.xml";
        params = [NSMutableDictionary dictionaryWithObjectsAndKeys:tweet, @"text", nil];
        NSString *name = [self.previewTweet valueForKeyPath:@"user.screen_name"];
        [params setValue:name forKey:@"screen_name"];
    }
    else if ([tweet isEqualToString:RT_IDENTIFIER_TEXT]) {
        if (NSString *id = [self.previewTweet objectForKey:@"id_str"]) {
            params = [NSMutableDictionary dictionary];
            url = [NSString stringWithFormat:@"https://api.twitter.com/1/statuses/retweet/%@.xml", id];
        }
    }
    else {
        params = [NSMutableDictionary dictionaryWithObjectsAndKeys:tweet, @"status", nil];
        if (NSString *id = [self.previewTweet objectForKey:@"id_str"])
            [params setValue:id forKey:@"in_reply_to_status_id"];

    }

    NSMutableArray *paramArray = [NSMutableArray arrayWithCapacity:params.count];
    for (id key in params)
        [paramArray addObject:[NSString stringWithFormat:@"%@=%@", [key encodedURLParameterString], [[params objectForKey:key] encodedURLParameterString]]];
    NSString *qs = [paramArray componentsJoinedByString:@"&"];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    [request setHTTPMethod:@"POST"];
    NSData *body = [qs dataUsingEncoding:NSUTF8StringEncoding];

    TwitterAuth *auth = [[[TwitterAuth alloc] init] autorelease];
    NSString *header = [auth OAuthorizationHeader:request.URL method:@"POST" body:body];
    [request setValue:header forHTTPHeaderField:@"Authorization"];
    [request setHTTPBody:body];

    NSError *error;
    /*NSData* data = */
    [NSURLConnection sendSynchronousRequest:request returningResponse:NULL error:&error];

    [[self.newTweetView.superview viewWithTag:575933] removeFromSuperview];
    self.newTweetView.hidden = NO;

    [pool release];
}

- (void)dismissTweet {
    [self.previewTextView resignFirstResponder];
    [self.plugin dismissPreview];
    [self hideKeyboard];
}

- (void)dismissDetailTweet {
    [self.webView resignFirstResponder];
    [self.plugin dismissPreview];
}


- (void)openInSelectedTwitterApp:(int)urlType  param:(NSString *)param {
    NSURL *url = [NSURL URLWithString:[self buildURLStringForTwitterApp:urlType param:param]];
    [self.plugin launchURL:url];
}

- (void)openProfileInSelectedTwitterApp {
    NSString *name = [self.previewTweet valueForKeyPath:@"user.screen_name"];
    [self openInSelectedTwitterApp:TYPE_PROFILE param:name];
}

- (void)openButtonPressed {
    NSString *id = [self.previewTweet objectForKey:@"id_str"];
    NSString *name = [self.previewTweet valueForKeyPath:@"user.screen_name"];
    BOOL isDM = ([self.previewTweet objectForKey:@"sender_id"] != nil);
    [self dismissDetailTweet];
    if (isDM)
        [self openInSelectedTwitterApp:TYPE_DIRECT_MESSAGE param:name];
    else
        [self openInSelectedTwitterApp:TYPE_STATUS param:id];
}

- (void)sendButtonPressed {
    [self sendTweet:self.previewTextView.text];
    [self dismissTweet];
}


- (BOOL)keyboardInput:(UITextView *)input shouldInsertText:(NSString *)text isMarkedText:(int)marked {
    if (input.text.length == 140)
        return NO;

    [self setCount:140 - input.text.length - text.length];
    return YES;
}

- (NSString *)parseTweetTextForReply:(NSString *)text {
    NSString *replyText = @"";
    NSArray *words = [text componentsSeparatedByString:@" "];
    replyText = @"";
    for (unsigned int i = 0; i < [words count]; i++) {
        NSString *token = [[words objectAtIndex:i] stringByAppendingString:@" "];
        if ([token hasPrefix:@"@"] && [replyText rangeOfString:token options:NSCaseInsensitiveSearch].location == NSNotFound) {
            replyText = [replyText stringByAppendingString:token];
        }
    }
    return [text isEqualToString:replyText] ? @"" : replyText;
}

- (UIView *)doTweet:(NSDictionary *)tweet isRetweet:(BOOL)isRetweet {
    self.navigationItem.title = localize(@"Compose");
    self.navigationItem.leftBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:localizeGlobal(@"Cancel") style:UIBarButtonItemStyleBordered target:self action:@selector(dismissTweet)] autorelease];
    self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:localizeGlobal(@"Send") style:UIBarButtonItemStyleDone target:self action:@selector(sendButtonPressed)] autorelease];

    self.previewTweet = tweet;

    if (self.isViewLoaded) {
        [self switchToWriteView];
        NSString *tweetText = [self.previewTweet objectForKey:@"text"];
        if (NSString *name = [self.previewTweet valueForKeyPath:@"user.screen_name"]) {
            if (isRetweet) {
                self.previewTextView.text = [NSString stringWithFormat:@"RT @%@ %@", name, tweetText];
            }
            else {
                BOOL isDM = ([self.previewTweet objectForKey:@"sender_id"] != nil);
                if (isDM) {
                    self.navigationItem.title = [NSString stringWithFormat:@"DM @%@", name];
                    self.previewTextView.text = @"";
                }
                else {
                    self.navigationItem.title = localize(@"Reply");
                    tweetText = [NSString stringWithFormat:@"@%@ %@", name, tweetText];
                    self.previewTextView.text = [self parseTweetTextForReply:tweetText];
                    self.previewTextView.selectedRange = NSMakeRange([self.previewTextView.text rangeOfString:@" "].location + 1, [self.previewTextView.text length]);
                }

            }
        }
        else
            self.previewTextView.text = @"";

        [self setCount:140 - self.previewTextView.text.length];
        [self.previewTextView becomeFirstResponder];

    }

    return self.previewController.view;
}

- (UIView *)showTweet:(NSDictionary *)tweet {
    return [self doTweet:tweet isRetweet:NO];
}


- (void)webViewDidStartLoad:(UIWebView *)webView {
    [self.activity startAnimating];
}

- (void)webViewDidFinishLoad:(UIWebView *)webView {
    [self.activity stopAnimating];
}

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType {

    NSURL *url = request.URL;
    if ([request.URL.scheme isEqualToString:@"litwitter"]) {
        NSString *hashOrUser = [[url absoluteString] substringFromIndex:[@"litwitter://a?o=" length]];
        if ([hashOrUser rangeOfString:@"@"].location == 0) {
            [self openInSelectedTwitterApp:TYPE_PROFILE param:hashOrUser];
        } else if ([hashOrUser rangeOfString:@"#"].location == 0) {
            [self openInSelectedTwitterApp:TYPE_SEARCH param:hashOrUser];
        }
    }
    else {
        [self.plugin launchURL:url];
    }
    return NO;
}

- (UIView *)showDetailTweet:(NSDictionary *)tweet {
    self.navigationItem.title = localize(@"Twitter");
    self.navigationItem.leftBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:localizeGlobal(@"Cancel") style:UIBarButtonItemStyleBordered target:self action:@selector(dismissDetailTweet)] autorelease];
    self.navigationItem.rightBarButtonItem = nil;

    self.previewTweet = tweet;

    if (self.isViewLoaded) {
        [self switchToReadView];
        [self fillDetailView:self.previewTweet];
    }
    NSArray *buttons = self.toolbarButtons;

    if(buttons == nil || [buttons count] <= 0){
        UIBarButtonItem *reply = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemReply target:self action:@selector(doReply)];
        UIBarButtonItem *flexspace = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
        UIBarButtonItem *open = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(openButtonPressed)];
        UIBarButtonItem *retweet = nil;
        
        UIImage *img = [UIImage li_imageWithContentsOfResolutionIndependentFile:[self.plugin.bundle pathForResource:@"LITwitterRetweet" ofType:@"png"]];
        retweet = [[UIBarButtonItem alloc] initWithImage:img style:UIBarButtonItemStylePlain target:self action:@selector(doRetweet)];
        buttons = [NSArray arrayWithObjects:reply, flexspace, retweet, flexspace, open, nil];
        
        self.toolbarItems = buttons;
        self.toolbarButtons = buttons;
        
        [reply release];
        [open release];
        [flexspace release];
        if (retweet != nil)
            [retweet release];
    }

    self.toolbarItems = self.toolbarButtons;     
    BOOL isDM = ([self.previewTweet objectForKey:@"sender_id"] != nil);
    [[self.toolbarItems objectAtIndex:2] setEnabled: !isDM];
    [self.previewController setToolbarHidden:NO];
    return self.previewController.view;
}

- (void)doReply {
    [self.previewController setToolbarHidden:YES];
    [self.plugin showPreview:[self showTweet:self.previewTweet]];
    [self switchToWriteView];

}

- (void)doRetweet {
    BOOL useOldRT = NO;
    if (NSNumber *n = [self.plugin.preferences objectForKey:@"UseOldRT"])
        useOldRT = n.boolValue;
    if (useOldRT) {
        [self.previewController setToolbarHidden:YES];
        [self.plugin showPreview:[self doTweet:self.previewTweet isRetweet:YES]];
        [self switchToWriteView];
    }
    else {
        [self performSelectorInBackground:@selector(sendTweetInBackground:) withObject:RT_IDENTIFIER_TEXT];
        [self dismissDetailTweet];
    }

}

- (NSString *)extractUsersFrom:(NSString *)token tweetText:(NSString *)tweetText {
    if (token == nil) {
        return @"";
    }
    NSCharacterSet *user = [NSCharacterSet characterSetWithCharactersInString:@"@"];
    NSCharacterSet *ignoredPunctuationsAndChars = [NSCharacterSet characterSetWithCharactersInString:@"!,:;.?()[]{}/\\`'\"<>#@"];
    int index = NSNotFound;
    int endIndex = NSNotFound;
    NSString *nextToken = nil;
    if ((index = [token rangeOfCharacterFromSet:user].location) != NSNotFound) {
        token = [token substringFromIndex:index];
        if ((endIndex = [[token substringFromIndex:1] rangeOfCharacterFromSet:ignoredPunctuationsAndChars].location) != NSNotFound) {
            endIndex++;
            nextToken = [token substringFromIndex:endIndex];
            token = [token substringToIndex:endIndex];
        }
        if ([tweetText rangeOfString:token options:NSCaseInsensitiveSearch].location == NSNotFound) {
            tweetText = [tweetText stringByAppendingString:token];
            tweetText = [tweetText stringByAppendingString:@" "];
        }
        tweetText = [tweetText stringByAppendingString:[self extractUsersFrom:nextToken tweetText:tweetText]];

    }
    return tweetText;
}

- (void)showNewTweet {
    UIView *v = [self showTweet:[NSDictionary dictionary]];
    [self.plugin showPreview:v];
}

- (void)resetTapCount {
    tapCount = 0;
}

- (UIView *)tableView:(LITableView *)tableView previewWithFrame:(CGRect)frame forRowAtIndexPath:(NSIndexPath *)indexPath {
    unsigned int row = indexPath.row - 1;//first row is for tabs
    if (row < self.tweets.count) {
        BOOL showPreview = YES;
        if (NSNumber *n = [self.plugin.preferences objectForKey:@"ShowPreview"])
            showPreview = n.boolValue;

        BOOL useDoubleTap = NO;
        if (NSNumber *n = [self.plugin.preferences objectForKey:@"UseDoubleTap"])
            useDoubleTap = n.boolValue;
        if (showPreview) {
            if (useDoubleTap) {
                tapCount++;
                if (tapCount == 2) {
                    tapCount = 0;
                    return [self showDetailTweet:[self.tweets objectAtIndex:row]];
                }
                else {
                    [self performSelector:@selector(resetTapCount) withObject:nil afterDelay:.4];
                    return nil;
                }
            }
            else {
                return [self showDetailTweet:[self.tweets objectAtIndex:row]];
            }
        }
        else
            return nil;
    }
    else {
        return [self showTweet:[NSDictionary dictionary]];
    }
}

- (CGFloat)tableView:(LITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row == 0) //first row is for tabs
        return 24;

    unsigned int row = indexPath.row - 1;
    if (row >= self.tweets.count)
        return 0;

    NSDictionary *elem = [self.tweets objectAtIndex:row];
    NSString *text = [elem objectForKey:@"text"];

    text = [@"         " stringByAppendingString:text];

    int width = (int) (tableView.frame.size.width - 10);
    CGSize s = [text sizeWithFont:tableView.theme.detailStyle.font constrainedToSize:CGSizeMake(width, 480) lineBreakMode:UILineBreakModeWordWrap];
    return (s.height + tableView.theme.summaryStyle.font.pointSize + 8);
}

- (NSInteger)tableView:(UITableView *)tableView numberOfItemsInSection:(NSInteger)section {
    unsigned int max = 5;
    if (NSNumber *n = [self.plugin.preferences objectForKey:@"MaxTweets"])
        max = n.intValue;

    return (self.tweets.count > max ? max : self.tweets.count);
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self tableView:tableView numberOfItemsInSection:section] + 1;
}

- (void)updateTweetsInView:(NSArray *)array {
    self.tweets = array;
    [self.plugin updateView:[NSDictionary dictionaryWithObjectsAndKeys:self.tweets, @"tweets", nil]];
}

- (void)switchToHomeline {
    [self updateTweetsInView:self.timeline];
}

- (void)switchToMentions {
    [self updateTweetsInView:self.mentions];
}

- (void)switchToMessages {
    [self updateTweetsInView:self.directMessages];
}


- (void)segmentAction:(id)sender {
    int selected = [sender selectedSegmentIndex];
    if (selectedIndex == selected)
        return;

    switch (selected) {
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

- (UITableViewCell *)tableView:(LITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    unsigned int row = indexPath.row;
    if (row == 0) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"TabsCell"];
        if (cell == nil) {
            CGRect frame = CGRectMake(0, -1, tableView.frame.size.width, 24);
            cell = [[[UITableViewCell alloc] initWithFrame:frame reuseIdentifier:@"TabsCell"] autorelease];

            UIImageView *iv = [[[UIImageView alloc] initWithImage:tableView.sectionSubheader] autorelease];
            iv.autoresizingMask = UIViewAutoresizingFlexibleWidth;
            iv.frame = frame;
            [cell.contentView addSubview:iv];

            UIView *container = [[[UIView alloc] initWithFrame:frame] autorelease];
            container.backgroundColor = [UIColor clearColor];
            container.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
            [cell.contentView addSubview:container];

            //!TODO localized labels
            NSArray *segmentTextContent = [NSArray arrayWithObjects:@"Timeline", @"Mentions", @"Messages", @"Compose", nil];
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
        BOOL newTweets = YES;
        if (NSNumber *n = [self.plugin.preferences objectForKey:@"NewTweets"])
            newTweets = n.boolValue;
        UISegmentedControl *segments = (UISegmentedControl *) [cell viewWithTag:43443];
        if (newTweets) //update segments based on NewTweets prefs
        {
            if (segments.numberOfSegments == 3)
                [segments insertSegmentWithTitle:@"Compose" atIndex:3 animated:NO];
        }
        else if (segments.numberOfSegments == 4) {
            [segments removeSegmentAtIndex:3 animated:NO];
        }

        segments.selectedSegmentIndex = selectedIndex;
        return cell;
    }
    row--;

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"TweetCell"];

    if (cell == nil) {
        CGRect frame = CGRectMake(0, 0, tableView.frame.size.width, 24);
        cell = [[[UITableViewCell alloc] initWithFrame:frame reuseIdentifier:@"TweetCell"] autorelease];

        TweetView *v = [[[TweetView alloc] initWithFrame:frame] autorelease];
        v.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        v.backgroundColor = [UIColor clearColor];
        v.tag = 57;
        [cell.contentView addSubview:v];
    }

    TweetView *v = (TweetView *) [cell.contentView viewWithTag:57];
    v.theme = tableView.theme;
    v.frame = CGRectMake(0, 0, tableView.frame.size.width, [self tableView:tableView heightForRowAtIndexPath:indexPath]);
    v.name = nil;
    v.tweet = nil;
    v.time = nil;

    if (row < self.tweets.count) {
        NSDictionary *elem = [self.tweets objectAtIndex:row];
        v.tweet = [elem objectForKey:@"text"];

        BOOL screenNames = false;
        if (NSNumber *b = [self.plugin.preferences objectForKey:@"UseScreenNames"])
            screenNames = b.boolValue;
        v.name = [elem valueForKeyPath:(screenNames ? @"user.screen_name" : @"user.name")];
        v.image = [self.imageCache objectForKey:[elem valueForKeyPath:@"user.profile_image_url"]];
        v.directMessage = ([elem objectForKey:@"direct_message"] != nil);

        NSNumber *dateNum = [elem objectForKey:@"date"];
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

static void callInterruptedApp(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    NSLog(@"LI:Twitter: Call interrupted app");
}

static void activeCallStateChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    NSLog(@"LI:Twitter: Call state changed");
}

- (id)initWithPlugin:(LIPlugin *)thePlugin {
    self = [super init];
    self.plugin = thePlugin;
    self.imageCache = [NSMutableDictionary dictionaryWithCapacity:10];
    self.tweets = [NSMutableArray arrayWithCapacity:10];
    self.mentions = [NSMutableArray arrayWithCapacity:10];
    self.timeline = [NSMutableArray arrayWithCapacity:10];
    self.directMessages = [NSMutableArray arrayWithCapacity:10];
    self.tempTweets = [NSMutableArray arrayWithCapacity:10];//[NSMutableDictionary dictionaryWithCapacity:20];
    lock = [[NSConditionLock alloc] init];
    formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [[[NSLocale alloc] initWithLocaleIdentifier:@"en_US"] autorelease];
    formatter.dateFormat = @"EEE MMM dd HH:mm:ss Z yyyy";

    thePlugin.tableViewDataSource = self;
    thePlugin.tableViewDelegate = self;
    thePlugin.previewDelegate = self;

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(update:) name:LITimerNotification object:nil];
    [center addObserver:self selector:@selector(update:) name:LIViewReadyNotification object:nil];


    //	Class $UIKeyboardImpl = objc_getClass("UIKeyboardImpl");
    //	Hook(UIKeyboardImpl, setDelegate:, setDelegate);

    //	Class $SBAwayController = objc_getClass("SBAwayController");
    //	Hook(SBAwayController, handleKeyEvent:, handleKeyEvent);

    if (directMessageIcon)
        [directMessageIcon release];

    directMessageIcon = [[UIImage li_imageWithContentsOfResolutionIndependentFile:[self.plugin.bundle pathForResource:@"LITwitterDirectMessage" ofType:@"png"]] retain];
    self.previewController = [[[UINavigationController alloc] initWithRootViewController:self] autorelease];
    UINavigationBar *navbar = self.previewController.navigationBar;
    navbar.barStyle = UIBarStyleBlackOpaque;
    UIToolbar *toolbar = [self.previewController toolbar];
    toolbar.barStyle = UIBarStyleBlackOpaque;

    return self;
}

- (void)dealloc {
    [formatter release];
    [lock release];
    [super dealloc];
}

- (BOOL)loadTweets:(NSString *)url parameters:(NSDictionary *)parameters {
    NSString *fullURL = url;
    if (parameters.count > 0) {
        NSMutableArray *paramArray = [NSMutableArray arrayWithCapacity:parameters.count];
        for (id key in parameters)
            [paramArray addObject:[NSString stringWithFormat:@"%@=%@", key, [parameters objectForKey:key]]];

        fullURL = [fullURL stringByAppendingFormat:@"?%@", [paramArray componentsJoinedByString:@"&"]];
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:fullURL]];
    request.HTTPMethod = @"GET";

    TwitterAuth *auth = [[[TwitterAuth alloc] init] autorelease];
    if (!auth.authorized) {
        NSLog(@"LI:Twitter: Twitter client is not authorized!");
        return NO;
    }

    NSString *header = [auth OAuthorizationHeader:request.URL method:@"GET" body:nil];
    [request setValue:header forHTTPHeaderField:@"Authorization"];
    NSError *anError = nil;
    NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:NULL error:&anError];

    if (data == nil) {
        return NO;
    }
    self.tempTweets = [data mutableObjectFromJSONData];
    if (self.tempTweets == nil || [self.tempTweets count] <= 0) {
        NSLog(@"LI:Twitter: Not enough tweets returned since last fetch");
        NSLog(@"LI:Twitter: RESPONSE: %@", [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease]);
        return NO;
    }
    return YES;
    
}

- (NSMutableArray *)_mergeArrays:(NSArray*)from to:(NSMutableArray*)to count:(int)count{
    if (to != nil && to.count > 0 && from.count < count) {
        for (NSDictionary *tweet in from) {
            [to insertObject:tweet atIndex:0];
            if (to.count > count) {
                [to removeObjectAtIndex:(to.count - 1)];
            }
        }
    } else {
        to = from;
    }
    return to;
}

- (void)_updateTweets:(BOOL) force {
    if (SBTelephonyManager * mgr = [$SBTelephonyManager sharedTelephonyManager]) {
        if (mgr.inCall || mgr.incomingCallExists) {
            NSLog(@"LI:Twitter: No data connection available.");
            return;
        }
    }

    NSLog(@"LI:Twitter: Loading tweets...");

    int count = 5;
    if (NSNumber *n = [self.plugin.preferences objectForKey:@"MaxTweets"])
        count = n.intValue;

    self.type = @"friend";
    NSString *sinceId = @"-1";
    if (!force && self.timeline && [self.timeline count] > 0) {
        sinceId = [[self.timeline objectAtIndex:0] objectForKey:@"id_str"];
    }
    NSArray *fetchedTweets = [NSArray array];
    NSMutableDictionary *params = [NSMutableDictionary dictionaryWithObjectsAndKeys:[NSString stringWithFormat:@"%d", count], @"count", nil];
    [params setObject:@"0" forKey:@"include_entities"];
    [params setObject:@"0" forKey:@"contributor_details"];
    if (![sinceId isEqualToString:@"-1"]) {
        [params setObject:sinceId forKey:@"since_id"];
    }
    if ([self loadTweets:@"https://api.twitter.com/statuses/home_timeline.json" parameters:params]) {
        if([self.tempTweets count] == 1) prepareObject([self.tempTweets objectAtIndex:0], self.imageCache);
        fetchedTweets = [self.tempTweets sortedArrayUsingFunction:prepareAndSortByDate context:self.imageCache];
        [self.tempTweets removeAllObjects];
        self.currentTweet = nil;
        self.timeline = force ? fetchedTweets : [self _mergeArrays:fetchedTweets to:[self.timeline mutableCopy] count:count];
        if (selectedIndex == 0 && self.timeline.count > 0) //load the view as soon as data is available
        {
            [self updateTweetsInView:self.timeline];
        }
    }
    self.type = @"mention";
    sinceId = @"-1";
    if (!force && self.mentions && [self.mentions count] > 0) {
        sinceId = [[self.mentions objectAtIndex:0] objectForKey:@"id_str"];
    }
    if (![sinceId isEqualToString:@"-1"]) {
        [params setObject:sinceId forKey:@"since_id"];
    } else {
        [params removeObjectForKey:@"since_id"];
    }
    if ([self loadTweets:@"https://api.twitter.com/statuses/mentions.json" parameters:params]) {
        if([self.tempTweets count] == 1) prepareObject([self.tempTweets objectAtIndex:0], self.imageCache);
        fetchedTweets = [self.tempTweets sortedArrayUsingFunction:prepareAndSortByDate context:self.imageCache];
        [self.tempTweets removeAllObjects];
        self.currentTweet = nil;
        self.mentions = force ? fetchedTweets : [self _mergeArrays:fetchedTweets to:[self.mentions mutableCopy] count:count];
        if (selectedIndex == 1 && self.mentions.count > 0) {
            [self updateTweetsInView:self.mentions];
        }
    }
    self.type = @"directMessage";
    sinceId = @"-1";
    if (!force && self.directMessages && [self.directMessages count] > 0) {
        sinceId = [[self.directMessages objectAtIndex:0] objectForKey:@"id_str"];
    }
    if (![sinceId isEqualToString:@"-1"]) {
        [params setObject:sinceId forKey:@"since_id"];
    } else {
        [params removeObjectForKey:@"since_id"];
    }
    if ([self loadTweets:@"https://api.twitter.com/1/direct_messages.json" parameters:params]) {
        if([self.tempTweets count] == 1) prepareObject([self.tempTweets objectAtIndex:0], self.imageCache);
        fetchedTweets = [self.tempTweets sortedArrayUsingFunction:prepareAndSortByDate context:self.imageCache];
        [self.tempTweets removeAllObjects];
        self.currentTweet = nil;
        self.directMessages = force ? fetchedTweets : [self _mergeArrays:fetchedTweets to:[self.directMessages mutableCopy] count:count];
        if (selectedIndex == 2 && self.directMessages.count > 0) {
            [self updateTweetsInView:self.directMessages];
        }
    }

    NSTimeInterval refresh = 900;
    if (NSNumber *n = [self.plugin.preferences objectForKey:@"RefreshInterval"]){
        refresh = n.intValue;
    }
    nextUpdate = [[NSDate dateWithTimeIntervalSinceNow:refresh] timeIntervalSinceReferenceDate];
    
}

- (void)updateTweets:(BOOL)force {
    if (!self.plugin.enabled)
        return;

    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    if ([lock tryLock]) {
        if (force || nextUpdate < [NSDate timeIntervalSinceReferenceDate])
            [self _updateTweets: force];

        [lock unlock];
    }

    [pool release];
}

- (void)update:(NSNotification *)notif {
    [self updateTweets:NO];
}

- (void)tableView:(LITableView *)tableView reloadDataInSection:(NSInteger)section {
    [self updateTweets:YES];
}

@end
