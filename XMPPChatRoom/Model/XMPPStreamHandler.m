//
//  XMPPStreamHandler.m
//  XMPPChatRoom
//
//  Created by hsusmita on 18/06/15.
//  Copyright (c) 2015 Susmita Horrow. All rights reserved.
//

#import "XMPPStreamHandler.h"

@interface XMPPStreamHandler()<XMPPStreamDelegate>
//{
//  XMPPStream *_xmppStream;
//}

@property (nonatomic, assign) BOOL customCertEvaluation;
@property (nonatomic, strong) NSString *password;

@property (nonatomic,copy) RequestCompletionBlock connectionCompletionBlock;
@property (nonatomic,copy) RequestCompletionBlock disconnectCompletionBlock;
@property (nonatomic,copy) RequestCompletionBlock authenticationCompletionBlock;
@property (nonatomic,copy) RequestCompletionBlock registerCompletionBlock;
@property (nonatomic,copy) RequestCompletionBlock messageSentCompletionBlock;
@property (nonatomic,copy) RequestCompletionBlock messageReceivedCompletionBlock;

@end

@implementation XMPPStreamHandler

- (instancetype)initWithServerName:(NSString *)name andPort:(UInt16)hostPort {
  if (self = [super init]) {
    _xmppStream = [[XMPPStream alloc]init];
    _xmppStream.hostName = name;
    _xmppStream.hostPort = hostPort;
    if ([[UIDevice currentDevice] isMultitaskingSupported]) {
      _xmppStream.enableBackgroundingOnSocket = YES;
    }
    [_xmppStream addDelegate:self delegateQueue:dispatch_get_main_queue()];
  }
  
  return self;
}

- (void)setupJID:(NSString *)JID andPassword:(NSString *)password {
  [self.xmppStream setMyJID:[XMPPJID jidWithString:JID]];
  self.password = password;
}

- (void)connectWithCompletionBlock:(RequestCompletionBlock)block {
  self.connectionCompletionBlock = block;
  if (self.xmppStream.isConnected) {
    if (block) {
      block(nil,YES,nil);
    }
  }else {
    NSError *error = nil;
    [self.xmppStream connectWithTimeout:XMPPStreamTimeoutNone error:&error];
    if (error && block) {
      block(nil,NO,error);
    }
  }
}

- (void)disconnectWithCompletionBlock:(RequestCompletionBlock)block {
  self.disconnectCompletionBlock = block;
  if (self.xmppStream.isDisconnected && block) {
    block(nil,YES,nil);
  }else {
    [self.xmppStream disconnect];
  }
}

- (void)authenticateWithCompletionBlock:(RequestCompletionBlock)block {
  self.authenticationCompletionBlock = block;
  NSError *error;
  [self.xmppStream authenticateWithPassword:self.password error:&error];
  if (error && block) {
    block(nil,NO,nil);
  }
}

- (void)registerWithCompletionBlock:(RequestCompletionBlock)block {
  self.registerCompletionBlock = block;
  NSError *error;
  [self.xmppStream registerWithPassword:self.password error:&error];
  if (error && block) {
    block(nil,NO,error);
  }
}


- (void)goOnline {
  XMPPPresence *presence = [XMPPPresence presence]; // type="available" is implicit
  NSLog(@"presence = %@",presence.type);
  [[self xmppStream] sendElement:presence];
}

- (void)goOffline {
  XMPPPresence *presence = [XMPPPresence presenceWithType:@"unavailable"];
  [[self xmppStream] sendElement:presence];
}

- (void)sendMessage:(NSString *)message
         toUsername:(NSString *)username
withCompletionBlock:(RequestCompletionBlock)completionBlock {
  if (message.length > 0) {
    NSXMLElement *body = [NSXMLElement elementWithName:@"body"];
    [body setStringValue:message];
    
    NSXMLElement *messageElement = [NSXMLElement elementWithName:@"message"];
    [messageElement addAttributeWithName:@"type" stringValue:@"chat"];
    [messageElement addAttributeWithName:@"to" stringValue:[NSString stringWithFormat:@"%@@%@",username,kHostName]];
    [messageElement addChild:body];
    [self.xmppStream sendElement:messageElement];
  }
}

- (void)handleMessageReceivedEventWithBlock:(RequestCompletionBlock)completionBlock {
  self.messageReceivedCompletionBlock = completionBlock;
}

- (void)tearDown {
  [self.xmppStream removeDelegate:self];
  [self.xmppStream disconnect];
}


#pragma mark XMPPStream Delegate

- (void)xmppStreamDidRegister:(XMPPStream *)sender {
  DDLogVerbose(@"%@: %@", THIS_FILE, THIS_METHOD);
  if (self.registerCompletionBlock) {
    self.registerCompletionBlock(nil,YES,nil);
  }
}

- (void)xmppStream:(XMPPStream *)sender didNotRegister:(NSXMLElement *)error {
  DDLogVerbose(@"%@: %@", THIS_FILE, THIS_METHOD);
  if (self.registerCompletionBlock) {
    self.registerCompletionBlock(nil,NO,nil);
  }
}

- (void)xmppStreamWillConnect:(XMPPStream *)sender {
  DDLogVerbose(@"%@: %@", THIS_FILE, THIS_METHOD);
}

- (void)xmppStream:(XMPPStream *)sender socketDidConnect:(GCDAsyncSocket *)socket {
  DDLogVerbose(@"%@: %@", THIS_FILE, THIS_METHOD);
}

- (void)xmppStreamDidStartNegotiation:(XMPPStream *)sender {
  DDLogVerbose(@"%@: %@", THIS_FILE, THIS_METHOD);
}

- (void)xmppStream:(XMPPStream *)sender willSecureWithSettings:(NSMutableDictionary *)settings {
  DDLogVerbose(@"%@: %@", THIS_FILE, THIS_METHOD);
  NSString *expectedCertName = [self.xmppStream.myJID domain];
  if (expectedCertName) {
    settings[(NSString *) kCFStreamSSLPeerName] = expectedCertName;
  }
  
  if (self.customCertEvaluation) {
    settings[GCDAsyncSocketManuallyEvaluateTrust] = @(YES);
  }
}

- (void)xmppStream:(XMPPStream *)sender didReceiveTrust:(SecTrustRef)trust
 completionHandler:(void (^)(BOOL shouldTrustPeer))completionHandler {
  DDLogVerbose(@"%@: %@", THIS_FILE, THIS_METHOD);
  // The delegate method should likely have code similar to this,
  // but will presumably perform some extra security code stuff.
  // For example, allowing a specific self-signed certificate that is known to the app.
  
  dispatch_queue_t bgQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
  dispatch_async(bgQueue, ^{
    
    SecTrustResultType result = kSecTrustResultDeny;
    OSStatus status = SecTrustEvaluate(trust, &result);
    
    if (status == noErr && (result == kSecTrustResultProceed || result == kSecTrustResultUnspecified)) {
      completionHandler(YES);
    }
    else {
      completionHandler(NO);
    }
  });
}

- (void)xmppStreamDidSecure:(XMPPStream *)sender {
  DDLogVerbose(@"%@: %@", THIS_FILE, THIS_METHOD);
}

- (void)xmppStreamDidConnect:(XMPPStream *)sender {
  DDLogVerbose(@"%@: %@", THIS_FILE, THIS_METHOD);  
  if (self.connectionCompletionBlock) {
    self.connectionCompletionBlock(nil,YES,nil);
  }
}

- (void)xmppStreamDidAuthenticate:(XMPPStream *)sender {
  DDLogVerbose(@"%@: %@", THIS_FILE, THIS_METHOD);
  if (self.authenticationCompletionBlock) {
    self.authenticationCompletionBlock(nil,YES,nil);
  }
}

- (void)xmppStream:(XMPPStream *)sender didNotAuthenticate:(NSXMLElement *)error {
  DDLogVerbose(@"%@: %@", THIS_FILE, THIS_METHOD);
  if (self.authenticationCompletionBlock) {
    self.authenticationCompletionBlock(nil,NO,nil);
  }
}

- (BOOL)xmppStream:(XMPPStream *)sender didReceiveIQ:(XMPPIQ *)iq {
  DDLogVerbose(@"%@: %@", THIS_FILE, THIS_METHOD);
  return NO;
}

- (void)xmppStream:(XMPPStream *)sender didReceiveMessage:(XMPPMessage *)message {
   DDLogVerbose(@"%@: %@", THIS_FILE, THIS_METHOD);
   NSLog(@"message = %@",message);
  if ([message isErrorMessage]) {
    self.messageReceivedCompletionBlock(nil,YES,message.errorMessage);

  }else {
    if (self.messageReceivedCompletionBlock) {
      NSArray *messages = [NSArray arrayWithObject:message];
      self.messageReceivedCompletionBlock(messages,YES,nil);
    }
  }
  
//      if ([[UIApplication sharedApplication] applicationState] == UIApplicationStateActive)
//        {
//          NSLog(@"Applications are in active state");
//          //send the above dictionary where ever you want
//        }
//      else
//        {
//        NSLog(@"Applications are in Inactive state");
//        UILocalNotification *localNotification = [[UILocalNotification alloc] init];
//        localNotification.alertAction = @"Ok";
//        localNotification.applicationIconBadgeNumber=count;
//        localNotification.alertBody =[NSString stringWithFormat:@"From:"%@\n\n%@",from,body];
//                                      [[UIApplication sharedApplication] presentLocalNotificationNow:localNotification];
//                                      //send the above dictionary where ever you want
//                                      }
//                                      }
 }

- (void)xmppStream:(XMPPStream *)sender didReceivePresence:(XMPPPresence *)presence {
  DDLogVerbose(@"%@: %@ - %@", THIS_FILE, THIS_METHOD, [presence type]);
  if ([presence isErrorPresence]) {
      NSLog(@"Error while present");
  }
  NSString *presenceType = [presence type];
  NSString *myUsername = [[sender myJID] user];
  NSString *presenceFromUser = [[presence from] user];

  if (![presenceFromUser isEqualToString:myUsername]) {
    
    if ([presenceType isEqualToString:@"available"]) {
      
//      [_chatDelegate newBuddyOnline:[NSString stringWithFormat:@"%@@%@", presenceFromUser, @"jerry.local"]];
      
    } else if ([presenceType isEqualToString:@"unavailable"]) {
      
//      [_chatDelegate buddyWentOffline:[NSString stringWithFormat:@"%@@%@", presenceFromUser, @"jerry.local"]];
    }
  }
}

- (void)xmppStream:(XMPPStream *)sender didReceiveError:(id)error {
  DDLogVerbose(@"%@: %@", THIS_FILE, THIS_METHOD);
}

- (void)xmppStreamDidDisconnect:(XMPPStream *)sender withError:(NSError *)error {
  DDLogVerbose(@"%@: %@", THIS_FILE, THIS_METHOD);
  NSLog(@"hostname = %@",sender.hostName);
  if (error) { //handle the case when this is called when connection attempt fails
    DDLogError(@"Unable to connect to server. Check xmppStream.hostName.error = %@",error);
    if (self.connectionCompletionBlock) {
      self.connectionCompletionBlock(nil,NO,error);
    }
  }else { //handle case when disconnect is called explicitly
    if (self.disconnectCompletionBlock) {
      self.disconnectCompletionBlock(nil,YES,nil);
    }
  }
}


@end
