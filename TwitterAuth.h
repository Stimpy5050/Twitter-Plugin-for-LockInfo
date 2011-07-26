//
//  OAuth.h
//
//  Created by Jaanus Kase on 12.01.10.
//  Copyright 2010. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface TwitterAuth : NSObject 

// If you detect a login state inconsistency in your app, use this to reset the context back to default,
// not-logged-in state.
- (void) forget;
-(BOOL) authorized;

// Twitter convenience methods
- (BOOL) requestTwitterToken;
- (BOOL) authorizeTwitterToken;

// Internal methods, no need to call these directly from outside.
- (NSString *) OAuthorizationHeader:(NSURL*) url method:(NSString *)method body:(NSData*) body;
- (NSString *) sha1:(NSString *)str;

@property (assign) BOOL oauth_token_authorized;
@property (retain) NSString *oauth_token;
@property (retain) NSString *oauth_token_secret;
@property (retain) NSString *user_id;
@property (retain) NSString *screen_name;
@property (retain) NSString *oauth_consumer_key;
@property (retain) NSString *oauth_consumer_secret;

@end
