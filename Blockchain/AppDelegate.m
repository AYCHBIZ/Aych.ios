//
//  AppDelegate.m
//  Blockchain
//
//  Created by Ben Reeves on 05/01/2012.
//  Copyright (c) 2012 Qkos Services Ltd. All rights reserved.
//
#import <QuartzCore/QuartzCore.h>

#import "AppDelegate.h"
#import "TransactionsViewController.h"
#import "MultiAddressResponse.h"
#import "Wallet.h"
#import "BCFadeView.h"
#import "TabViewController.h"
#import "ReceiveCoinsViewController.h"
#import "SendViewController.h"
#import "AccountViewController.h"
#import "TransactionsViewController.h"
#import "WebViewController.h"
#import "NewAccountView.h"
#import "NSString+SHA256.h"
#import "JSONKit.h"
#import "Transaction.h"
#import "Input.h"
#import "Output.h"
#import "UIDevice+Hardware.h"
#import "UncaughtExceptionHandler.h"
#import "UITextField+Blocks.h"
#import "PairingCodeParser.h"

AppDelegate * app;

@implementation AppDelegate

@synthesize window = _window;
@synthesize wallet;
@synthesize modalView;
@synthesize latestResponse;

#pragma mark - Lifecycle

-(id)init {
    if (self = [super init]) {
         
        btcFormatter = [[NSNumberFormatter alloc] init];
        [btcFormatter setMaximumSignificantDigits:5];
        [btcFormatter setMaximumFractionDigits:5];
        [btcFormatter setNumberStyle:NSNumberFormatterDecimalStyle];
        
        localCurrencyFormatter = [[NSNumberFormatter alloc] init];
        [localCurrencyFormatter setMaximumFractionDigits:2];
        [localCurrencyFormatter setNumberStyle:NSNumberFormatterDecimalStyle];

        self.modalChain = [[[NSMutableArray alloc] init] autorelease];
        
        app = self;
        
    }
    return self;
}


- (void)installUncaughtExceptionHandler
{
	InstallUncaughtExceptionHandler();
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    [self performSelector:@selector(installUncaughtExceptionHandler) withObject:nil afterDelay:0];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:LOADING_TEXT_NOTIFICAITON_KEY object:nil queue:nil usingBlock:^(NSNotification * notification) {
        
        self.loadingText = [notification object];
    }];
    
    // Override point for customization after application launch.
    _window.backgroundColor = [UIColor whiteColor];
    
    [_window makeKeyAndVisible];
    
    tabViewController = oldTabViewController;
    
    [_window setRootViewController:tabViewController];
    
    [tabViewController setActiveViewController:transactionsViewController];

    [_window.rootViewController.view addSubview:busyView];
    
    busyView.frame = _window.frame;
    busyView.alpha = 0.0f;

    if ([self guid]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(.2f * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self showPinModal];
        });
    }
    
    if (![self guid] || ![self sharedKey]) {
        [self showWelcome];
    } else if (![self password]) {
        [self showModal:mainPasswordView isClosable:FALSE];
        
        [mainPasswordTextField becomeFirstResponder];
    } else {
        
        NSString * guid = [self guid];
        NSString * sharedKey = [self sharedKey];
        NSString * password = [self password];
        
        NSLog(@"didFinishLaunchingWithOptions GUID %@", guid);
        
        if (guid && sharedKey && password) {
            self.wallet = [[[Wallet alloc] initWithGuid:guid sharedKey:sharedKey password:password] autorelease];
            
            self.wallet.delegate = self;
        }
    }
    
    return YES;
}

- (void)transitionToIndex:(NSInteger)newIndex
{
    if (newIndex == 0)
        [self transactionsClicked:nil];
    else if (newIndex == 1)
        [self receiveCoinClicked:nil];
    else if (newIndex == 2)
        [self sendCoinsClicked:nil];
    else if (newIndex == 3)
        [self infoClicked:nil];
    else
        NSLog(@"Unknown tab index: %d", newIndex);
}

- (void)swipeLeft
{
    if (tabViewController.selectedIndex < 3)
    {
        NSInteger newIndex = tabViewController.selectedIndex + 1;
        [self transitionToIndex:newIndex];
    }
}

- (void)swipeRight
{
    if (tabViewController.selectedIndex)
    {
        NSInteger newIndex = tabViewController.selectedIndex - 1;
        [self transitionToIndex:newIndex];
    }
}

-(IBAction)balanceTextClicked:(id)sender {
    [self toggleSymbol];
}

#pragma mark - UI State
-(void)toggleSymbol {
    symbolLocal = !symbolLocal;
    
    [transactionsViewController setText];
    [[transactionsViewController tableView] reloadData];
}

-(void)setDisableBusyView:(BOOL)__disableBusyView {
    _disableBusyView = __disableBusyView;
    
    if (_disableBusyView) {
        [busyView removeFromSuperview];
    }
    else {
        [_window.rootViewController.view addSubview:busyView];
//        [_window bringSubviewToFront:busyView];
    }
}

-(void)networkActivityStart {
    [busyView fadeIn];

    [powerButton setEnabled:FALSE];

    if (self.loadingText) {
        [busyLabel setText:self.loadingText];
    }
    
    [self setStatus];
}

-(void)networkActivityStop {
    [powerButton setEnabled:TRUE];

    [busyView fadeOut];
    
    [activity stopAnimating];
    
    [self setStatus];
}

-(void)setStatus {
    if ([app.wallet getWebsocketReadyState] != 1) {
        [powerButton setHighlighted:TRUE];
    } else {
        [powerButton setHighlighted:FALSE];
    }
}

#pragma mark - AlertView Helpers

- (void)standardNotify:(NSString*)message
{
	[self standardNotify:message title:@"Error" delegate:nil];
}

- (void)standardNotify:(NSString*)message delegate:(id)fdelegate
{
	[self standardNotify:message title:@"Error" delegate:fdelegate];
}

- (void)standardNotify:(NSString*)message title:(NSString*)title delegate:(id)fdelegate
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([[UIApplication sharedApplication] applicationState] == UIApplicationStateActive) {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title message:message  delegate:fdelegate cancelButtonTitle:@"OK" otherButtonTitles: nil];
            [alert show];
            [alert release];
        }
    });
}

-(void)didGenerateNewWallet:(Wallet*)_wallet password:(NSString*)password {
    
    [self forgetWallet];

    self.wallet = _wallet;
    
    [[NSUserDefaults standardUserDefaults] setObject:wallet.guid forKey:@"guid"];
    [[NSUserDefaults standardUserDefaults] setObject:wallet.sharedKey forKey:@"sharedKey"];
    [[NSUserDefaults standardUserDefaults] setObject:password forKey:@"password"];
    
    [[NSUserDefaults standardUserDefaults] synchronize];
}

-(void)walletDidLoad:(Wallet *)_wallet {      
    NSLog(@"walletDidLoad");

    [self setAccountData:wallet.guid sharedKey:wallet.sharedKey password:wallet.password];
    
    [transactionsViewController reload];
    [receiveViewController reload];
    [sendViewController reload];
    
    [app closeModal];
}

-(void)didGetMultiAddressResponse:(MulitAddressResponse*)response {
    self.latestResponse = response;

    transactionsViewController.data = response;
    
    [transactionsViewController reload];
    [receiveViewController reload];
    [sendViewController reload];
}

-(void)didSetLatestBlock:(LatestBlock*)block {
    transactionsViewController.latestBlock = block;
}

-(void)walletFailedToDecrypt:(Wallet*)_wallet {    
    
    _wallet.password = nil;
    
    //Clear the password and refetch the wallet data
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"password"];
    
    //Cleare the checksum cache incase it has
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"checksum_cache"];

    [self showModal:mainPasswordView isClosable:FALSE];
    
    [mainPasswordTextField becomeFirstResponder];
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    if ([self guid]) {
        [self showPinModal];
    }
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    
    if (![self guid] || ![self sharedKey]) {
        [app showWelcome];
        return;
    }
    
    if (!wallet.password) {
        [self walletFailedToDecrypt:wallet];
    }

    [self.wallet getHistory];    
}

-(void)playBeepSound {
    
	if (beepSoundID == 0) {
		AudioServicesCreateSystemSoundID((CFURLRef)[NSURL fileURLWithPath: [[NSBundle mainBundle] pathForResource:@"beep" ofType:@"wav"]], &beepSoundID);
	}
	
	AudioServicesPlaySystemSound(beepSoundID);		
}

-(void)playAlertSound {
    
	if (alertSoundID == 0) {
		//Find the Alert Sound
		NSString * alert_sound = [[NSBundle mainBundle] pathForResource:@"alert-received" ofType:@"wav"];
		
		//Create the system sound
		AudioServicesCreateSystemSoundID((CFURLRef)[NSURL fileURLWithPath: alert_sound], &alertSoundID);
	}
	
	AudioServicesPlaySystemSound(alertSoundID);		
}


// Only gets called when displaying a transaction hash
-(void)pushWebViewController:(NSString*)url {
    webViewController = [[WebViewController alloc] init];
    [webViewController viewDidLoad]; // ??

    [tabViewController setActiveViewController:webViewController animated:YES index:-1];

    [webViewController loadURL:url];
}

- (NSMutableDictionary *)parseQueryString:(NSString *)query {
    NSMutableDictionary *dict = [[[NSMutableDictionary alloc] initWithCapacity:6] autorelease];
    NSArray *pairs = [query componentsSeparatedByString:@"&"];
    
    for (NSString *pair in pairs) {
        NSArray *elements = [pair componentsSeparatedByString:@"="];
        NSString *key = [[elements objectAtIndex:0] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        NSString *val = [[elements objectAtIndex:1] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        
        [dict setObject:val forKey:key];
    }
    return dict;
}

-(NSDictionary*)parseURI:(NSString*)urlString {
    
    if (![urlString hasPrefix:@"bitcoin:"]) {
        return [NSDictionary dictionaryWithObject:urlString forKey:@"address"];
    }
        
    NSString * replaced = [[urlString stringByReplacingOccurrencesOfString:@"bitcoin:" withString:@"bitcoin://"] stringByReplacingOccurrencesOfString:@"////" withString:@"//"];
    
    NSURL * url = [NSURL URLWithString:replaced];
    
    NSMutableDictionary *dict = [self parseQueryString:[url query]];

    if ([url host] != NULL)
        [dict setObject:[url host] forKey:@"address"];
    
    return dict;
}

- (BOOL)application:(UIApplication *)application handleOpenURL:(NSURL *)url
{
    [app closeModal];
    
    NSDictionary *dict = [self parseURI:[url absoluteString]];
        
    NSString * addr = [dict objectForKey:@"address"];
    NSString * amount = [dict objectForKey:@"amount"];

    [self showSendCoins];
    
    [sendViewController setToAddressFromUrlHandler:addr];
    
    [sendViewController setAmount:amount];

    return YES;
}


-(TransactionsViewController*)transactionsViewController {
    return transactionsViewController;
}

-(TabViewcontroller*)tabViewController {
    return tabViewController;
}

- (BOOL)textFieldShouldReturn:(UITextField*)aTextField
{
    [aTextField resignFirstResponder];
    
    return YES;
}

-(void)getPrivateKeyPassword:(void (^)(NSString *))success error:(void (^)(NSString *))error {
    
    validateSecondPassword = FALSE;
    
    secondPasswordDescriptionLabel.text = @"The private key you are attempting to import is encrypted. Please enter the password below.";

    [app showModal:secondPasswordView isClosable:TRUE onDismiss:^() {
        NSString * password = secondPasswordTextField.text;
        
        if ([password length] == 0) {
            if (error) error(@"No Password Entered");
        } else {
            if (success) success(password);
        }
        
        secondPasswordTextField.text = nil;
    } onResume:nil];
    
    [secondPasswordTextField becomeFirstResponder];
}

-(IBAction)secondPasswordClicked:(id)sender {
    NSString * password = secondPasswordTextField.text;
    
    if (!validateSecondPassword || [wallet validateSecondPassword:password]) {
        [app closeModal];
    } else {
        [app standardNotify:@"Second Password Incorrect"];
        secondPasswordTextField.text = nil;
    }
}

-(void)getSecondPassword:(void (^)(NSString *))success error:(void (^)(NSString *))error {
    
    secondPasswordDescriptionLabel.text = @"This action requires the second password for your bitcoin wallet. Please enter it below and press continue.";
    
    validateSecondPassword = TRUE;
    
    [app showModal:secondPasswordView isClosable:TRUE onDismiss:^() {
        NSString * password = secondPasswordTextField.text;
                    
        if ([password length] == 0) {
            if (error) error(@"No Password Entered");
        } else if(![wallet validateSecondPassword:password]) {
            if (error) error(@"Second Password Incorrect");
        } else {
            if (success) success(password);
        }
        
        secondPasswordTextField.text = nil;
    } onResume:nil];
    
    [secondPasswordTextField becomeFirstResponder];
}


-(void)closeModal {
    [modalView removeFromSuperview];
    [modalView.modalContentView removeFromSuperview];
    
    CATransition *animation = [CATransition animation];
    [animation setDuration:ANIMATION_DURATION];
    [animation setType:kCATransitionFade];
    
    [animation setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear]];
    [[_window layer] addAnimation:animation forKey:@"HideModal"];
    
    if (self.modalView.onDismiss) {
        self.modalView.onDismiss();
        self.modalView.onDismiss = nil;
    }
    
    self.modalView.modalContentView = nil;
    self.modalView = nil;
    
    if ([self.modalChain count] > 0) {
        MyUIModalView * previousModalView = [self.modalChain objectAtIndex:[self.modalChain count]-1];
        
        [_window.rootViewController.view addSubview:previousModalView];

        [_window.rootViewController.view bringSubviewToFront:busyView];

        [_window.rootViewController.view endEditing:TRUE];
        
        if (self.modalView.onResume) {
            self.modalView.onResume();
        }
        
        self.modalView = previousModalView;
        
        [self.modalChain removeObjectAtIndex:[self.modalChain count]-1];
    }
}

-(void)showModal:(UIView*)contentView isClosable:(BOOL)_isClosable {
    [self showModal:contentView isClosable:_isClosable onDismiss:nil onResume:nil];
}

-(void)showModal:(UIView*)contentView isClosable:(BOOL)_isClosable onDismiss:(void (^)())onDismiss onResume:(void (^)())onResume {
    
    @try {        
        //Cannot re-display a modal which is already in the modalChain
        for (MyUIModalView * chainModal in self.modalChain) {
            if (chainModal.modalContentView == contentView) {
                return;
            }
        }
        
        if (modalView) {
            [modalView removeFromSuperview];

            if (modalView.isClosable) {
                [modalView.modalContentView removeFromSuperview];

                if (self.modalView.onDismiss) {
                    self.modalView.onDismiss();
                    self.modalView.onDismiss = nil;
                }
                
                self.modalView.modalContentView = nil;
            } else {
                [self.modalChain addObject:modalView];
            }
            
            self.modalView = nil;
        }
        
        [[NSBundle mainBundle] loadNibNamed:@"ModalView" owner:self options:nil];
        
        [modalView.modalContentView addSubview:contentView];
        
        modalView.isClosable = _isClosable;
        
        self.modalView.onDismiss = onDismiss;
        self.modalView.onResume = onResume;
        
        if (onResume) {
            onResume();
        }
        
        contentView.frame = CGRectMake(0, 0, modalView.modalContentView.frame.size.width, modalView.modalContentView.frame.size.height);
        
        [_window.rootViewController.view addSubview:modalView];
        
        [_window.rootViewController.view bringSubviewToFront:busyView];
        
        [_window.rootViewController.view endEditing:TRUE];
     } @catch (NSException * e) {
         [UncaughtExceptionHandler logException:e];
     }
    
    @try {
        CATransition *animation = [CATransition animation]; 
        [animation setDuration:ANIMATION_DURATION];
        [animation setType:kCATransitionFade];
        [animation setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear]];
        [[_window.rootViewController.view layer] addAnimation:animation forKey:@"ShowModal"];
    } @catch (NSException * e) {
        NSLog(@"Animation Exception %@", e);
    }
}

-(void)didFailBackupWallet:(Wallet*)wallet {
    //Don't know a safe way to recover
    //Just clear everything and restart
    
    [self.wallet cancelTxSigning];
    
    self.wallet = nil;
    self.latestResponse = nil;
    
    transactionsViewController.data = nil;
    [transactionsViewController reload];
    [receiveViewController reload];
    [sendViewController reload];
    
    [accountViewController emptyWebView];
    
    self.wallet = [[[Wallet alloc] initWithGuid:[self guid] sharedKey:[self sharedKey] password:[self password]] autorelease];
    
    self.wallet.delegate = app;
}

-(void)didBackupWallet:(Wallet*)wallet {
    [transactionsViewController reload];
    [receiveViewController reload];
    [sendViewController reload];
}

-(void)setAccountData:(NSString*)guid sharedKey:(NSString*)sharedKey password:(NSString*)password {

    if ([guid length] != 36) {
        [app standardNotify:@"Invalid GUID"];
        return;
    }
    
    if ([sharedKey length] != 36) {
        [app standardNotify:@"Invalid Shared Key"];
        return;
    }
    
    if ([password length] < 10) {
        [app standardNotify:@"Password should be 10 characters in length or more"];
        return;
    }
    
    [[NSUserDefaults standardUserDefaults] setObject:guid forKey:@"guid"];
    [[NSUserDefaults standardUserDefaults] setObject:sharedKey forKey:@"sharedKey"];
    [[NSUserDefaults standardUserDefaults] setObject:password forKey:@"password"];
    
    [[NSUserDefaults standardUserDefaults] synchronize];

    [app closeModal];
}

-(BOOL)isZBarSupported {
    NSUInteger platformType = [[UIDevice currentDevice] platformType];
    
    if (platformType ==  UIDeviceiPhoneSimulator || platformType ==  UIDeviceiPhoneSimulatoriPhone  || platformType ==  UIDeviceiPhoneSimulatoriPhone || platformType ==  UIDevice1GiPhone || platformType ==  UIDevice3GiPhone || platformType ==  UIDevice1GiPod || platformType ==  UIDevice2GiPod || ![UIImagePickerController isSourceTypeAvailable: UIImagePickerControllerSourceTypeCamera]) {
        return FALSE;
    }
    
    return TRUE;
}

-(IBAction)manualPairClicked:(id)sender {
    
    NSString * guid = manualIdentifier.text;
    NSString * password = manualPassword.text;
    
    self.wallet = [[[Wallet alloc] initWithGuid:guid password:password] autorelease];
    
    self.wallet.delegate = app;
    
    [app closeModal];
}


-(IBAction)scanAccountQRCodeclicked:(id)sender {
    
    if ([self isZBarSupported]) {
        PairingCodeParser * parser = [[PairingCodeParser alloc] init];
        
        [parser scanAndParse:^(NSDictionary*code) {
            self.wallet = [[[Wallet alloc] initWithGuid:[code objectForKey:@"guid"] sharedKey:[code objectForKey:@"sharedKey"] password:[code objectForKey:@"password"]] autorelease];
            
            self.wallet.delegate = self;

        } error:^(NSString*error) {
            [app standardNotify:error];
        }];
    } else {
        [self showModal:manualView isClosable:TRUE];
    }
}

-(void)logout {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"password"];
    [[NSUserDefaults standardUserDefaults] synchronize];

    [self.wallet cancelTxSigning];

    self.wallet = nil;
    self.latestResponse = nil;
    
    transactionsViewController.data = nil;
    [transactionsViewController reload];
    [receiveViewController reload];
    [sendViewController reload];
    [accountViewController emptyWebView];
}

-(void)forgetWallet {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"guid"];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"sharedKey"];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"password"];
    
    [[NSUserDefaults standardUserDefaults] synchronize];   
    
    self.wallet = nil;
    self.latestResponse = nil;
    [transactionsViewController setData:nil];
}

#pragma mark - Show Screens

// Modal menu
-(void)showWelcome {
    [app showModal:welcomeView isClosable:[self guid] != nil onDismiss:nil onResume:^() {
        
        [changePINButton setHidden:![self isPINSet]];
        
        // User is logged in
        if ([self password]) {
            welcomeLabel.text = @"Options";
            welcomeInstructionsLabel.text = @"Logout or change your pin below.";
            createWalletButton.hidden = YES;
            [pairLogoutButton setTitle:@"Logout" forState:UIControlStateNormal];
        }
        // Wallet paired, but no password
        else if ([self guid] || [self sharedKey]) {
            welcomeLabel.text = @"Welcome Back";
            welcomeInstructionsLabel.text = @"";
            createWalletButton.hidden = YES;
            [pairLogoutButton setTitle:@"Forget Details" forState:UIControlStateNormal];
        }
        // User is completed logged out
        else {
            welcomeLabel.text = @"Welcome to Blockchain Wallet";
            welcomeInstructionsLabel.text = @"If you already have a Blockchain Wallet, choose Pair Device; otherwise, choose Create Wallet.    It's Free! No email required.";
            createWalletButton.hidden = NO;
            [pairLogoutButton setTitle:@"Pair Device" forState:UIControlStateNormal];
        }
    }];
}

-(void)showSendCoins {
    
    if (!sendViewController) {
        sendViewController = [[SendViewController alloc] initWithNibName:@"SendCoins" bundle:[NSBundle mainBundle]];
        
        [sendViewController viewDidLoad];
    }
    
    [tabViewController setActiveViewController:sendViewController  animated:TRUE index:2];
}

-(void)clearPin {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"pin"];
}

-(BOOL)isPINSet {
    return [[NSUserDefaults standardUserDefaults] objectForKey:@"pin"] != nil;
}

- (void)showPinModal
{
    // if pin exists - verify
    if ([self isPINSet])
    {
        self.pinEntryViewController = [PEPinEntryController pinVerifyController];
    }
    // no pin - create
    else
    {
        self.pinEntryViewController = [PEPinEntryController pinCreateController];
    }
    
    self.pinEntryViewController.navigationBarHidden = YES;
    self.pinEntryViewController.pinDelegate = self;
    
    [_window.rootViewController presentViewController:self.pinEntryViewController animated:NO completion:nil];
//    [_window bringSubviewToFront:self.pinEntryViewController.view];
}

#pragma mark - AlertView Delegate

-(void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {

    if ([alertView tag] == kTagAlertForgetWallet)
    {
        // Forget Wallet Cancelled
        if (buttonIndex == 0) {
        }
        // Forget Wallet Confirmed
        else if (buttonIndex == 1) {
            NSLog(@"forgetting wallet");
            [app closeModal];
            [self forgetWallet];
            [app showWelcome];
        }
    }
}

#pragma mark - Actions

-(IBAction)changePinClicked:(id)sender {
    PEPinEntryController *c = [PEPinEntryController pinChangeController];
    c.pinDelegate = self;
    c.navigationBarHidden = YES;
    
    PEViewController *peViewController = (PEViewController *)[[c viewControllers] objectAtIndex:0];
    peViewController.cancelButton.hidden = NO;
    
    [self.tabViewController presentViewController:c animated:YES completion:nil];
}

-(IBAction)powerClicked:(id)sender {
    [self showWelcome];
}

-(IBAction)signupClicked:(id)sender {
    [app showModal:newAccountView isClosable:TRUE];
}

-(IBAction)loginClicked:(id)sender {
    // Logout
    if ([self password]) {
        [self logout];
        
        [app closeModal];
        
        [self walletFailedToDecrypt:wallet]; // misleading method name
    }
    // Forget wallet
    else if ([self guid] || [self sharedKey]) {
        
        // confirm forget wallet
        
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Warning!!!"
                                                        message:@"This will erase all wallet data on this device. Please confirm your wallet has been backed up to blockchain.info before forgetting this wallet. Forgetting a wallet that has not been backed up to blockchain.info will result in permanent loss of any bitcoin in this wallet!"
                                                       delegate:self
                                              cancelButtonTitle:@"Cancel"
                                              otherButtonTitles:@"Forget Wallet", nil];
        alert.delegate = self;
        alert.tag = kTagAlertForgetWallet;
        [alert show];
        [alert release];

    }
    // Welcome
    else {
        [app showModal:pairingInstructionsView isClosable:TRUE];
    }
}

-(IBAction)receiveCoinClicked:(UIButton *)sender {
    if (!receiveViewController) {
        receiveViewController = [[ReceiveCoinsViewController alloc] initWithNibName:@"ReceiveCoins" bundle:[NSBundle mainBundle]];
        
        [receiveViewController viewDidLoad];
    }
        
    [tabViewController setActiveViewController:receiveViewController animated:TRUE index:1];
}

-(IBAction)transactionsClicked:(UIButton *)sender {
    [tabViewController setActiveViewController:transactionsViewController animated:TRUE index:0];
}

-(IBAction)sendCoinsClicked:(UIButton *)sender {
    [self showSendCoins];
}

-(IBAction)infoClicked:(UIButton *)sender {
    if (!accountViewController) {
        accountViewController = [[AccountViewController alloc] initWithNibName:@"AccountViewController" bundle:[NSBundle mainBundle]];
        
        [accountViewController viewDidLoad];
    }
    
    [tabViewController setActiveViewController:accountViewController animated:TRUE index:3];
}

-(IBAction)mainPasswordClicked:(id)sender {
    
    NSString * password = mainPasswordTextField.text;
    
    password = [password stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    if ([mainPasswordTextField.text length] < 10) {
        [app standardNotify:@"Passowrd must be 10 or more characters in length"];
        return;
    }
    
    [[NSUserDefaults standardUserDefaults] setObject:password forKey:@"password"];
    
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    NSString * guid = [[NSUserDefaults standardUserDefaults] objectForKey:@"guid"];
    NSString * sharedKey = [[NSUserDefaults standardUserDefaults] objectForKey:@"sharedKey"];
    
    if (guid && sharedKey && password) {
        self.wallet = [[[Wallet alloc] initWithGuid:guid sharedKey:sharedKey password:password] autorelease];
        
        self.wallet.delegate = self;
    }
    
    mainPasswordTextField.text = nil;
    
    [app closeModal];
}

-(IBAction)refreshClicked:(id)sender {
    if (![self guid] || ![self sharedKey]) {
        [app showWelcome];
        return;
    }
    
    if (wallet.password) {
        [self.wallet getHistory];
    } else {
        [self walletFailedToDecrypt:wallet];
    }
}

-(IBAction)modalBackgroundClicked:(id)sender {
    [modalView endEditing:FALSE];
}

#pragma mark - Accessors

-(NSString*)password {
    return [[NSUserDefaults standardUserDefaults] objectForKey:@"password"];
}

-(NSString*)guid {
    return [[NSUserDefaults standardUserDefaults] objectForKey:@"guid"];
}

-(NSString*)sharedKey {
    return [[NSUserDefaults standardUserDefaults] objectForKey:@"sharedKey"];
}

#pragma mark - Pin Entry Delegates

- (BOOL)pinEntryController:(PEPinEntryController *)c shouldAcceptPin:(NSUInteger)pin
{
    NSNumber *pinObj = [[NSUserDefaults standardUserDefaults] objectForKey:@"pin"];
    
	if(pinObj && pin == [pinObj intValue])
    {
		if(c.verifyOnly == YES)
        {
			[tabViewController dismissViewControllerAnimated:YES completion:^{
            }];
		}
        
		return YES;
	}
    else
    {
		return NO;
	}
}

- (void)pinEntryController:(PEPinEntryController *)c changedPin:(NSUInteger)pin
{
    [[NSUserDefaults standardUserDefaults] setValue:[NSNumber numberWithInt:pin] forKey:@"pin"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    NSLog(@"Saved new pin");
    
	// Update your info to new pin code
	[tabViewController dismissViewControllerAnimated:YES completion:nil];
}

- (void)pinEntryControllerDidCancel:(PEPinEntryController *)c
{
	NSLog(@"Pin change cancelled!");
	[tabViewController dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Format helpers

-(NSString*)formatMoney:(uint64_t)value localCurrency:(BOOL)fsymbolLocal {
    if (fsymbolLocal && latestResponse.symbol_local.conversion) {
        @try {
            BOOL negative = false;
            
            NSDecimalNumber * number = [(NSDecimalNumber*)[NSDecimalNumber numberWithLongLong:value] decimalNumberByDividingBy:(NSDecimalNumber*)[NSDecimalNumber numberWithDouble:(double)latestResponse.symbol_local.conversion]];
            
            if ([number compare:[NSNumber numberWithInt:0]] < 0) {
                number = [number decimalNumberByMultiplyingBy:[NSDecimalNumber decimalNumberWithString:@"-1"]];
                negative = TRUE;
            }
            
            if (negative)
                return [@"-" stringByAppendingString:[latestResponse.symbol_local.symbol stringByAppendingString:[localCurrencyFormatter stringFromNumber:number]]];
            else
                return [latestResponse.symbol_local.symbol stringByAppendingString:[localCurrencyFormatter stringFromNumber:number]];
            
        } @catch (NSException * e) {
            NSLog(@"%@", e);
        }
    } else if (latestResponse.symbol_btc) {
        NSDecimalNumber * number = [(NSDecimalNumber*)[NSDecimalNumber numberWithLongLong:value] decimalNumberByDividingBy:(NSDecimalNumber*)[NSDecimalNumber numberWithLongLong:latestResponse.symbol_btc.conversion]];
        
        NSString * string = [btcFormatter stringFromNumber:number];
        
        if ([string length] >= 8) {
            string = [string substringToIndex:8];
        }
        
        return [string stringByAppendingFormat:@" %@", latestResponse.symbol_btc.symbol];
    }
    
    NSDecimalNumber * number = [(NSDecimalNumber*)[NSDecimalNumber numberWithLongLong:value] decimalNumberByDividingBy:(NSDecimalNumber*)[NSDecimalNumber numberWithDouble:SATOSHI]];
    
    NSString * string = [btcFormatter stringFromNumber:number];
    
    if ([string length] >= 8) {
        string = [string substringToIndex:8];
    }
    
    return [string stringByAppendingString:@" BTC"];
}

-(NSString*)formatMoney:(uint64_t)value {
    return [self formatMoney:value localCurrency:symbolLocal];
}

@end
