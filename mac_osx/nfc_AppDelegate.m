//
//  AppDelegate.m
//  nfc_socket_client
//
//  Created by WozniBob on 6/19/15.
//  Copyright (c) 2015 Bob_Burns. All rights reserved.
//

#import "AppDelegate.h"
#import <errno.h>
#import <fcntl.h>
#import <stdbool.h>
#import <string.h>
#import <unistd.h>
#import <arpa/inet.h>   // inet_ntop()
#import <netdb.h>       //gethostbyname2()
#import <netinet/in.h>  // struct sockaddr_in
#import <netinet6/in6.h>    //struct sockaddr_in6
#import <sys/socket.h>      // socket(), AF_INET
#import <sys/types.h>

#define MAX_MESSAGE_SIZE (UINT8_MAX)
#define READ_BUFFER_SIZE (256)

static const in_port_t kPortNumber = 2342;
static const int kInvalidSocket = -1;

static int WriteMessage (int fd, const void *buffer, size_t length);
static int SocketConnectedToHostNamed (const char *hostname);
static bool GetAddressAtIndex (struct hostent *host, int addressIndex,
                               struct sockaddr_storage *outServerAddress);


#define debug 1

@interface AppDelegate () {
    CFSocketNativeHandle _sockfd;
    CFSocketRef _socketRef;
}

@property (weak) IBOutlet NSWindow *window;
@property (strong) NSInputStream *inputStream;
@property (strong) NSOutputStream *outStream;
@property (strong) NSMutableData *dataToRead;
@property (strong) NSMutableData *dataToWrite;
@property NSInteger bytesRead;
@property (nonatomic, readonly, getter=isConnected) BOOL connected;

- (void) updateUI;
- (void) runErrorMessage: (NSString *)message withError:(int)err;

// Connection
- (void)connectToHost: (NSString *)hostname asUser:(NSString *)pass;
- (void)closeConnection;

// Socket
- (void)startMonitoringSocket;
- (void)stopMonitoringSocket;

// RunLoop
static void ReceiveMessage (CFSocketRef, CFSocketCallBackType, CFDataRef, const void *, void *);

- (void)handleMessageData: (NSData *)data;

- (IBAction)scanButton:(id)sender;
- (IBAction)closeButton:(id)sender;
- (IBAction)connect:(id)sender;

@property (weak) IBOutlet NSTextField *connectedLabel;
@property (weak) IBOutlet NSTextField *creditLabel;
@property (weak) IBOutlet NSTextField *nameLable;
@property (weak) IBOutlet NSTextField *scanLabel;
@property (weak) IBOutlet NSProgressIndicator *pIndicate;

@property (weak) IBOutlet NSSecureTextField *passField;
@end

@implementation AppDelegate

- (id)init {
    if ((self = [super init])) {
        _sockfd = kInvalidSocket;
    }
    return self;
}

- (void)dealloc {
    [self closeConnection];
}


- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Insert code here to initialize your application
    [_pIndicate setStyle:NSProgressIndicatorSpinningStyle];
    [_scanLabel setHidden:YES];
    [self updateUI];
}

- (BOOL)isConnected {
    BOOL connected = (_socketRef != NULL);
    return connected;
}

- (void)startStream {
    
    
}

- (void)handleData:(NSMutableData *)data {
    
}

- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)eventCode {
    
    
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

- (IBAction)scanButton:(id)sender {
    if (_sockfd == kInvalidSocket) return;
    
    [_pIndicate startAnimation:self];
    [_scanLabel setHidden:NO];
    uint8_t cmd_buf[3];
    cmd_buf[0] = 0x80;      //opcode
    cmd_buf[1] = 0x01;      //length
    cmd_buf[2] = 0x20;      //cmd
    
    int nwritten = WriteMessage(_sockfd, cmd_buf, 3);
    if (nwritten == 3) printf("write scan successful!\n");
    
}

- (IBAction)closeButton:(id)sender {
    
    if (_sockfd == kInvalidSocket) return;
    
    //tell server we are closing socket
    uint8_t cmd_buf[3];
    cmd_buf[0] = 0x80;      //opcode
    cmd_buf[1] = 0x01;      //length
    cmd_buf[2] = 0x80;      //cmd
    
    int nwritten = WriteMessage(_sockfd, cmd_buf, 3);
    if (nwritten == 3) printf("write close successful!\n");
    
    [self closeConnection];
    
    [self updateUI];
}

- (IBAction)connect:(id)sender {
    NSString *hostname = @"xx.xx.xx.xx"
    NSString *pass = [_passField stringValue];
    [self connectToHost:hostname asUser:pass];
    
    [self updateUI];
    
    if ([self isConnected]) {
        NSLog(@"Connected!");
    }
}

- (void) updateUI {
    const BOOL connected = [self isConnected];
    [_connectedLabel setStringValue:connected ? @"Connected" : @"Not Connected"];
    
}

- (void)runErrorMessage:(NSString *)message withError:(int)err {
    NSString *errorString = @"";
    if (err != 0) {
        errorString = ([NSString stringWithUTF8String:strerror(err)]);
    }
    
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Error occured!"];
    [alert setInformativeText:errorString];
    [alert runModal];
}

- (void)connectToHost:(NSString *)hostname asUser:(NSString *)pass {
    NSString *errorMessage = nil;
    int sysError = noErr;
    
    if (_sockfd != kInvalidSocket) [self closeConnection];
    
    if (hostname.length < 1) {
        errorMessage = @"Hostname must not be empty";
        goto bailout;
    }
    if (pass.length == 0 || pass.length > 8) {
        errorMessage = @"Password must be between 1 and 8 characters long.";
        goto bailout;
    }
    const char *hostnameCtr = [hostname UTF8String];
    _sockfd = SocketConnectedToHostNamed(hostnameCtr);
    
    const char *passwrd = [pass UTF8String];
    NSUInteger passlen = strlen(passwrd);
    
    int nwritten = WriteMessage(_sockfd, passwrd, passlen);
    
    if (nwritten == -1) {
        errorMessage = @"Failed to send username.";
        sysError = errno;
        goto bailout;
    }
    
    //Make the socket non-blocking
    int err = fcntl(_sockfd, F_SETFL, O_NONBLOCK);
    if (err == -1) {
        errorMessage = @"Couldn't put socket into non-blocking mode";
        sysError = errno;
        goto bailout;
    }
    
    [self startMonitoringSocket];
    
bailout:
    if (errorMessage != nil) {
        [self runErrorMessage:errorMessage withError:sysError];
        [self closeConnection];
    }
    return;
}

- (void)closeConnection {
    [self stopMonitoringSocket];
    close(_sockfd);
    _sockfd = kInvalidSocket;
}

- (void)startMonitoringSocket {
    CFSocketContext context = {0, (__bridge void *)(self), NULL, NULL, NULL};
    _socketRef = CFSocketCreateWithNative(kCFAllocatorDefault,
                                          _sockfd,
                                          kCFSocketDataCallBack,
                                          ReceiveMessage,
                                          &context);
    if (_socketRef == NULL) {
        [self runErrorMessage:@"Unable to create CFSocketRef." withError:noErr];
        goto bailout;
    }
    
    CFRunLoopSourceRef rls = CFSocketCreateRunLoopSource(kCFAllocatorDefault, _socketRef, 0);
    if (rls == NULL) {
        [self runErrorMessage:@"Unable to create socket run loop source." withError:noErr];
        goto bailout;
    }
    
    CFRunLoopAddSource(CFRunLoopGetCurrent(), rls, kCFRunLoopDefaultMode);
    CFRelease(rls);
    
bailout:
    return;
}

- (void)stopMonitoringSocket {
    if (_socketRef != NULL) {
        CFSocketInvalidate(_socketRef);
        CFRelease(_socketRef);
        _socketRef = NULL;
    }
}

static void ReceiveMessage (CFSocketRef socket, CFSocketCallBackType type,
                            CFDataRef address, const void *data, void *info) {
    AppDelegate *self = (__bridge AppDelegate *)(info);
    [self handleMessageData:(__bridge NSData *)(data)];
    
}

- (void)handleMessageData:(NSData *)data {
    // Closed connection?
    if (data.length == 0) {
        [self closeConnection];
        [self runErrorMessage:@"The server closed the connection." withError:noErr];
        return;
    }
    uint8_t byteArray[256];
    int credits;
    const unsigned char* name;
    [data getBytes:byteArray length:256];
    NSLog(@"byte array: %s", byteArray);
    if (byteArray[0] == 0x82) {
        switch (byteArray[2]) {
            case 0xA1:
                credits = byteArray[3] + (byteArray[4] * 256);
                [_creditLabel setStringValue:[NSString stringWithFormat:@"%d",credits]];
                break;
            case 0xF0:
                [_nameLable setStringValue:@"Invalid Password"];
                break;
                
            default:
                break;
        }
    }
    if (byteArray[0] == 0x81) {
        name = &byteArray[2];        // points to name string
        [_nameLable setStringValue:[NSString stringWithUTF8String:(char *)name]];
        [_pIndicate stopAnimation:self];
        [_scanLabel setHidden:YES];
    }
    
}

static int SocketConnectedToHostNamed(const char *hostname) {
    int sockfd = -1;
    sa_family_t family[] = {AF_INET6, AF_INET };
    int family_count = sizeof(family) / sizeof(*family);
    
    for (int i=0; sockfd == -1 && i < family_count; i++) {
        printf("Looking at %s family:\n", family[i] == AF_INET6 ? "AF_INET6" : "AF_INET");
        
        // Get host address.
        struct hostent *host = NULL;
        host = gethostbyname2(hostname, family[i]);
        if (host == NULL) {
            herror("gethostbyname2");
            continue;
        }
        
        // Try to connect with each address.
        struct sockaddr_storage server_addr;
        
        for (int addressIndex = 0; sockfd == -1; addressIndex++) {
            // grab the next address. Bail our if we've run out.
            if (!GetAddressAtIndex(host, addressIndex, &server_addr)) break;
            
            char buffer[INET6_ADDRSTRLEN];
            
            printf("Trying %s...\n",
                   inet_ntop(host->h_addrtype, host->h_addr_list[addressIndex],
                             buffer, sizeof(buffer)));
            
            // Get a socket
            sockfd = socket(server_addr.ss_family, SOCK_STREAM, 0);
            
            if (sockfd == -1) {
                perror("    socket");
                continue;
            }
            // connect
            int err = connect(sockfd, (struct sockaddr *)&server_addr, server_addr.ss_len);
            if (err == -1) {
                perror("    connect");
                close(sockfd);
                sockfd = -1;
            }
            //success
        }
    }
    return sockfd;
}

static bool GetAddressAtIndex(struct hostent *host, int addressIndex,
                              struct sockaddr_storage *outServerAddress) {
    if (outServerAddress == NULL || host == NULL) return false;
    // Out of Addresses?
    if (host->h_addr_list[addressIndex] == NULL) return false;
    
    outServerAddress->ss_family = host->h_addrtype;
    
    if (outServerAddress->ss_family == AF_INET6) {
        struct sockaddr_in6 *addr = (struct sockaddr_in6 *)outServerAddress;
        addr->sin6_len = sizeof(*addr);
        addr->sin6_port = htons(kPortNumber);
        addr->sin6_flowinfo = 0;
        addr->sin6_addr = *(struct in6_addr *)host->h_addr_list[addressIndex];
        addr->sin6_scope_id = 0;
    } else {
        struct sockaddr_in *addr = (struct sockaddr_in *)outServerAddress;
        addr->sin_len = sizeof(*addr);
        addr->sin_port = htons(kPortNumber);
        addr->sin_addr = *(struct in_addr *)host->h_addr_list[addressIndex];
        memset(&addr->sin_zero, 0, sizeof(addr->sin_zero));
    }
    return true;
}

static int WriteMessage (int fd, const void*buffer, size_t length) {
    // Message never longer than 256 bytes!
    // Write opcode then length
    uint8_t bytesLeft = (uint8_t)length;
    uint8_t header[1];
    header[0] = bytesLeft;
    ssize_t nwritten = write(fd, header, sizeof(header));
    if (nwritten <=0) goto bailout;
    
    while (bytesLeft > 0) {
        nwritten = write(fd, buffer, bytesLeft);
        bytesLeft -= nwritten;
        buffer += nwritten;     //advance pointer
    }
    
bailout:
    if (nwritten == -1) perror("write");
    return (int)nwritten;
}

@end
