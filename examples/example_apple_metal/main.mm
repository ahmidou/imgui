// Dear ImGui: standalone example application for OSX + Metal.
// Uses CAMetalLayer directly (instead of MTKView) for glitch-free resizing.
// Based on Tristan Hume's MetalLayerView pattern with presentsWithTransaction.

// Learn about Dear ImGui:
// - FAQ                  https://dearimgui.com/faq
// - Getting Started      https://dearimgui.com/getting-started
// - Documentation        https://dearimgui.com/docs (same as your local docs/ folder).
// - Introduction, links and more at the top of imgui.cpp

#import <Foundation/Foundation.h>

#if TARGET_OS_OSX
#import <Cocoa/Cocoa.h>
#import <CoreVideo/CoreVideo.h>
#else
#import <UIKit/UIKit.h>
#endif

#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

#include "imgui.h"
#include "imgui_impl_metal.h"
#if TARGET_OS_OSX
#include "imgui_impl_osx.h"
#endif

//-----------------------------------------------------------------------------------
// Forward declarations
//-----------------------------------------------------------------------------------

@class MetalLayerView;

// Render callback type: the view calls this to draw a frame
typedef void (^RenderCallback)(CAMetalLayer* layer, CGSize viewSize, CGFloat scaleFactor);

//-----------------------------------------------------------------------------------
// MetalLayerView — custom view backed by CAMetalLayer
//-----------------------------------------------------------------------------------

#if TARGET_OS_OSX

@interface MetalLayerView : NSView <CALayerDelegate>
@property (nonatomic, strong) CAMetalLayer* metalLayer;
@property (nonatomic, copy) RenderCallback renderCallback;
@end

@implementation MetalLayerView

-(instancetype)initWithFrame:(NSRect)frame device:(id<MTLDevice>)device
{
    self = [super initWithFrame:frame];
    if (self)
    {
        self.wantsLayer = YES;
        self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawDuringViewResize;
        self.layerContentsPlacement = NSViewLayerContentsPlacementScaleAxesIndependently;

        _metalLayer = (CAMetalLayer*)self.layer;
        _metalLayer.device = device;
        _metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
        _metalLayer.delegate = self;
        _metalLayer.allowsNextDrawableTimeout = NO;
        _metalLayer.autoresizingMask = kCALayerHeightSizable | kCALayerWidthSizable;
        _metalLayer.needsDisplayOnBoundsChange = YES;
        _metalLayer.presentsWithTransaction = YES;
    }
    return self;
}

-(CALayer*)makeBackingLayer
{
    CAMetalLayer* layer = [CAMetalLayer layer];
    return layer;
}

-(BOOL)wantsUpdateLayer { return YES; }

-(void)setFrameSize:(NSSize)newSize
{
    [super setFrameSize:newSize];
    _metalLayer.drawableSize = [self convertSizeToBacking:newSize];
}

-(void)viewDidChangeBackingProperties
{
    [super viewDidChangeBackingProperties];
    if (self.window)
        _metalLayer.contentsScale = self.window.backingScaleFactor;
}

-(void)displayLayer:(CALayer*)layer
{
    if (_renderCallback)
    {
        CGFloat scale = self.window.backingScaleFactor ?: NSScreen.mainScreen.backingScaleFactor;
        _renderCallback(_metalLayer, self.bounds.size, scale);
    }
}

@end

#else // iOS

@interface MetalLayerView : UIView
@property (nonatomic, strong) CAMetalLayer* metalLayer;
@property (nonatomic, copy) RenderCallback renderCallback;
@property (nonatomic, strong) CADisplayLink* displayLink;
@end

@implementation MetalLayerView

+(Class)layerClass
{
    return [CAMetalLayer class];
}

-(instancetype)initWithFrame:(CGRect)frame device:(id<MTLDevice>)device
{
    self = [super initWithFrame:frame];
    if (self)
    {
        _metalLayer = (CAMetalLayer*)self.layer;
        _metalLayer.device = device;
        _metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
        _metalLayer.framebufferOnly = YES;
        self.contentScaleFactor = UIScreen.mainScreen.scale;
        _metalLayer.drawableSize = CGSizeMake(frame.size.width * self.contentScaleFactor,
                                               frame.size.height * self.contentScaleFactor);
    }
    return self;
}

-(void)layoutSubviews
{
    [super layoutSubviews];
    _metalLayer.drawableSize = CGSizeMake(self.bounds.size.width * self.contentScaleFactor,
                                           self.bounds.size.height * self.contentScaleFactor);
}

-(void)startDisplayLink
{
    _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(displayLinkFired:)];
    [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

-(void)stopDisplayLink
{
    [_displayLink invalidate];
    _displayLink = nil;
}

-(void)displayLinkFired:(CADisplayLink*)link
{
    if (_renderCallback)
    {
        CGFloat scale = self.contentScaleFactor;
        _renderCallback(_metalLayer, self.bounds.size, scale);
    }
}

@end

#endif

//-----------------------------------------------------------------------------------
// AppViewController
//-----------------------------------------------------------------------------------

#if TARGET_OS_OSX
@interface AppViewController : NSViewController<NSWindowDelegate>
@end
#else
@interface AppViewController : UIViewController
@end
#endif

@interface AppViewController ()
@property (nonatomic, strong) MetalLayerView* metalView;
@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) id<MTLRenderPipelineState> trianglePipelineState;
@property (nonatomic, strong) id<MTLBuffer> triangleVertexBuffer;
#if TARGET_OS_OSX
@property (nonatomic, assign) CVDisplayLinkRef displayLink;
#endif
@end

@implementation AppViewController

-(instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];

    _device = MTLCreateSystemDefaultDevice();
    _commandQueue = [_device newCommandQueue];

    if (!self.device)
    {
        NSLog(@"Metal is not supported");
        abort();
    }

    // Setup Dear ImGui context
    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO(); (void)io;
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;     // Enable Keyboard Controls
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableGamepad;      // Enable Gamepad Controls
    io.ConfigFlags |= ImGuiConfigFlags_DockingEnable;         // Enable Docking
    io.ConfigFlags |= ImGuiConfigFlags_ViewportsEnable;       // Enable Multi-Viewport / Platform Windows

    // Setup Dear ImGui style
    ImGui::StyleColorsDark();

    // When viewports are enabled we tweak WindowRounding/WindowBg so platform windows can look identical to regular ones.
    ImGuiStyle& style = ImGui::GetStyle();
    if (io.ConfigFlags & ImGuiConfigFlags_ViewportsEnable)
    {
        style.WindowRounding = 0.0f;
        style.Colors[ImGuiCol_WindowBg].w = 1.0f;
    }

    // Setup Renderer backend
    ImGui_ImplMetal_Init(_device);

    // Setup triangle pipeline and vertex buffer
    {
        NSString* shaderSource = @
            "#include <metal_stdlib>\n"
            "using namespace metal;\n"
            "struct VertexIn {\n"
            "    float2 position [[attribute(0)]];\n"
            "    float4 color    [[attribute(1)]];\n"
            "};\n"
            "struct VertexOut {\n"
            "    float4 position [[position]];\n"
            "    float4 color;\n"
            "};\n"
            "vertex VertexOut triangle_vertex(VertexIn in [[stage_in]]) {\n"
            "    VertexOut out;\n"
            "    out.position = float4(in.position, 0.0, 1.0);\n"
            "    out.color = in.color;\n"
            "    return out;\n"
            "}\n"
            "fragment float4 triangle_fragment(VertexOut in [[stage_in]]) {\n"
            "    return in.color;\n"
            "}\n";

        NSError* error = nil;
        id<MTLLibrary> library = [_device newLibraryWithSource:shaderSource options:nil error:&error];
        if (!library)
            NSLog(@"Failed to compile triangle shader: %@", error);

        MTLVertexDescriptor* vertexDesc = [MTLVertexDescriptor vertexDescriptor];
        vertexDesc.attributes[0].format = MTLVertexFormatFloat2;
        vertexDesc.attributes[0].offset = 0;
        vertexDesc.attributes[0].bufferIndex = 0;
        vertexDesc.attributes[1].format = MTLVertexFormatFloat4;
        vertexDesc.attributes[1].offset = sizeof(float) * 2;
        vertexDesc.attributes[1].bufferIndex = 0;
        vertexDesc.layouts[0].stride = sizeof(float) * 6;

        MTLRenderPipelineDescriptor* pipelineDesc = [[MTLRenderPipelineDescriptor alloc] init];
        pipelineDesc.vertexFunction = [library newFunctionWithName:@"triangle_vertex"];
        pipelineDesc.fragmentFunction = [library newFunctionWithName:@"triangle_fragment"];
        pipelineDesc.vertexDescriptor = vertexDesc;
        pipelineDesc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
        pipelineDesc.colorAttachments[0].blendingEnabled = NO;

        _trianglePipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineDesc error:&error];
        if (!_trianglePipelineState)
            NSLog(@"Failed to create triangle pipeline: %@", error);

        // Triangle vertices: position (x, y) + color (r, g, b, a)
        float vertexData[] = {
             0.0f,  0.5f,   1.0f, 0.0f, 0.0f, 1.0f,  // top - red
            -0.5f, -0.5f,   0.0f, 1.0f, 0.0f, 1.0f,  // bottom-left - green
             0.5f, -0.5f,   0.0f, 0.0f, 1.0f, 1.0f,  // bottom-right - blue
        };
        _triangleVertexBuffer = [_device newBufferWithBytes:vertexData
                                                     length:sizeof(vertexData)
                                                    options:MTLResourceStorageModeShared];
    }

    return self;
}

-(void)loadView
{
#if TARGET_OS_OSX
    self.metalView = [[MetalLayerView alloc] initWithFrame:CGRectMake(0, 0, 1200, 800) device:self.device];
#else
    self.metalView = [[MetalLayerView alloc] initWithFrame:UIScreen.mainScreen.bounds device:self.device];
#endif
    self.view = self.metalView;
}

-(void)viewDidLoad
{
    [super viewDidLoad];

#if TARGET_OS_OSX
    ImGui_ImplOSX_Init(self.view);
    [NSApp activateIgnoringOtherApps:YES];
#endif

    // Setup render callback — captures self weakly to avoid retain cycle
    __weak AppViewController* weakSelf = self;
    self.metalView.renderCallback = ^(CAMetalLayer* layer, CGSize viewSize, CGFloat scaleFactor) {
        [weakSelf renderWithLayer:layer viewSize:viewSize scaleFactor:scaleFactor];
    };

#if TARGET_OS_OSX
    // Start CVDisplayLink for continuous rendering
    CVDisplayLinkCreateWithActiveCGDisplays(&_displayLink);
    CVDisplayLinkSetOutputCallback(_displayLink, &displayLinkCallback, (__bridge void*)self.metalView);
    CVDisplayLinkStart(_displayLink);
#else
    [self.metalView startDisplayLink];
#endif
}

#if TARGET_OS_OSX
static CVReturn displayLinkCallback(CVDisplayLinkRef displayLink,
                                     const CVTimeStamp* now,
                                     const CVTimeStamp* outputTime,
                                     CVOptionFlags flagsIn,
                                     CVOptionFlags* flagsOut,
                                     void* context)
{
    MetalLayerView* view = (__bridge MetalLayerView*)context;
    dispatch_async(dispatch_get_main_queue(), ^{
        [view setNeedsDisplay:YES];
    });
    return kCVReturnSuccess;
}
#endif

-(void)renderWithLayer:(CAMetalLayer*)layer viewSize:(CGSize)viewSize scaleFactor:(CGFloat)scaleFactor
{
    ImGuiIO& io = ImGui::GetIO();
    io.DisplaySize.x = viewSize.width;
    io.DisplaySize.y = viewSize.height;
    io.DisplayFramebufferScale = ImVec2(scaleFactor, scaleFactor);

    id<CAMetalDrawable> drawable = [layer nextDrawable];
    if (!drawable)
        return;

    // Build render pass descriptor manually
    MTLRenderPassDescriptor* renderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
    renderPassDescriptor.colorAttachments[0].texture = drawable.texture;
    renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
    renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;

    // Start the Dear ImGui frame
    ImGui_ImplMetal_NewFrame(renderPassDescriptor);
#if TARGET_OS_OSX
    ImGui_ImplOSX_NewFrame(self.view);
#endif
    ImGui::NewFrame();

    // Our state (make them static = more or less global) as a convenience to keep the example terse.
    static bool show_demo_window = true;
    static bool show_another_window = false;
    static ImVec4 clear_color = ImVec4(0.45f, 0.55f, 0.60f, 1.00f);

    // 1. Show the big demo window
    if (show_demo_window)
        ImGui::ShowDemoWindow(&show_demo_window);

    // 2. Show a simple window that we create ourselves.
    {
        static float f = 0.0f;
        static int counter = 0;

        ImGui::Begin("Hello, world!");

        ImGui::Text("This is some useful text.");
        ImGui::Checkbox("Demo Window", &show_demo_window);
        ImGui::Checkbox("Another Window", &show_another_window);

        ImGui::SliderFloat("float", &f, 0.0f, 1.0f);
        ImGui::ColorEdit3("clear color", (float*)&clear_color);

        if (ImGui::Button("Button"))
            counter++;
        ImGui::SameLine();
        ImGui::Text("counter = %d", counter);

        ImGui::Text("Application average %.3f ms/frame (%.1f FPS)", 1000.0f / io.Framerate, io.Framerate);
        ImGui::End();
    }

    // 3. Show another simple window.
    if (show_another_window)
    {
        ImGui::Begin("Another Window", &show_another_window);
        ImGui::Text("Hello from another window!");
        if (ImGui::Button("Close Me"))
            show_another_window = false;
        ImGui::End();
    }

    // Rendering
    ImGui::Render();
    ImDrawData* draw_data = ImGui::GetDrawData();

    renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(
        clear_color.x * clear_color.w, clear_color.y * clear_color.w,
        clear_color.z * clear_color.w, clear_color.w);

    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
    id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];

    double fbWidth = (double)(draw_data->DisplaySize.x * draw_data->FramebufferScale.x);
    double fbHeight = (double)(draw_data->DisplaySize.y * draw_data->FramebufferScale.y);

    // Draw background triangle with 1:1 aspect ratio viewport
    {
        double size = fmin(fbWidth, fbHeight);
        MTLViewport triViewport = {
            .originX = (fbWidth - size) * 0.5,
            .originY = (fbHeight - size) * 0.5,
            .width = size,
            .height = size,
            .znear = 0.0,
            .zfar = 1.0
        };
        [renderEncoder setViewport:triViewport];
        [renderEncoder pushDebugGroup:@"Background Triangle"];
        [renderEncoder setRenderPipelineState:self.trianglePipelineState];
        [renderEncoder setVertexBuffer:self.triangleVertexBuffer offset:0 atIndex:0];
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
        [renderEncoder popDebugGroup];
    }

    // Reset viewport to full framebuffer for ImGui
    MTLViewport viewport = {
        .originX = 0.0,
        .originY = 0.0,
        .width = fbWidth,
        .height = fbHeight,
        .znear = 0.0,
        .zfar = 1.0
    };
    [renderEncoder setViewport:viewport];

    // Draw ImGui
    [renderEncoder pushDebugGroup:@"Dear ImGui rendering"];
    ImGui_ImplMetal_RenderDrawData(draw_data, commandBuffer, renderEncoder);
    [renderEncoder popDebugGroup];
    [renderEncoder endEncoding];

#if TARGET_OS_OSX
    // Synchronous present for glitch-free resizing
    [commandBuffer commit];
    [commandBuffer waitUntilScheduled];
    [drawable present];
#else
    [commandBuffer presentDrawable:drawable];
    [commandBuffer commit];
#endif

    // Update and Render additional Platform Windows
    if (io.ConfigFlags & ImGuiConfigFlags_ViewportsEnable)
    {
        ImGui::UpdatePlatformWindows();
        ImGui::RenderPlatformWindowsDefault();
    }
}

-(void)shutdown
{
#if TARGET_OS_OSX
    if (_displayLink)
    {
        CVDisplayLinkStop(_displayLink);
        CVDisplayLinkRelease(_displayLink);
        _displayLink = NULL;
    }
#else
    [self.metalView stopDisplayLink];
#endif

    ImGui_ImplMetal_Shutdown();
#if TARGET_OS_OSX
    ImGui_ImplOSX_Shutdown();
#endif
    ImGui::DestroyContext();
}

-(void)dealloc
{
    [self shutdown];
}

//-----------------------------------------------------------------------------------
// Input processing
//-----------------------------------------------------------------------------------

#if TARGET_OS_OSX

-(void)viewWillAppear
{
    [super viewWillAppear];
    self.view.window.delegate = self;
}

-(void)windowWillClose:(NSNotification *)notification
{
}

#else

// This touch mapping is super cheesy/hacky. We treat any touch on the screen
// as if it were a depressed left mouse button, and we don't bother handling
// multitouch correctly at all. This causes the "cursor" to behave very erratically
// when there are multiple active touches. But for demo purposes, single-touch
// interaction actually works surprisingly well.
-(void)updateIOWithTouchEvent:(UIEvent *)event
{
    UITouch *anyTouch = event.allTouches.anyObject;
    CGPoint touchLocation = [anyTouch locationInView:self.view];
    ImGuiIO &io = ImGui::GetIO();
    io.AddMouseSourceEvent(ImGuiMouseSource_TouchScreen);
    io.AddMousePosEvent(touchLocation.x, touchLocation.y);

    BOOL hasActiveTouch = NO;
    for (UITouch *touch in event.allTouches)
    {
        if (touch.phase != UITouchPhaseEnded && touch.phase != UITouchPhaseCancelled)
        {
            hasActiveTouch = YES;
            break;
        }
    }
    io.AddMouseButtonEvent(0, hasActiveTouch);
}

-(void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event      { [self updateIOWithTouchEvent:event]; }
-(void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event      { [self updateIOWithTouchEvent:event]; }
-(void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event  { [self updateIOWithTouchEvent:event]; }
-(void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event      { [self updateIOWithTouchEvent:event]; }

#endif

@end

//-----------------------------------------------------------------------------------
// AppDelegate
//-----------------------------------------------------------------------------------

#if TARGET_OS_OSX

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (nonatomic, strong) NSWindow *window;
@end

@implementation AppDelegate

-(BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    return YES;
}

-(instancetype)init
{
    if (self = [super init])
    {
        NSViewController *rootViewController = [[AppViewController alloc] initWithNibName:nil bundle:nil];
        self.window = [[NSWindow alloc] initWithContentRect:NSZeroRect
                                                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
        self.window.contentViewController = rootViewController;
        [self.window center];
        [self.window makeKeyAndOrderFront:self];
    }
    return self;
}

@end

#else

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow *window;
@end

@implementation AppDelegate

-(BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary<UIApplicationLaunchOptionsKey,id> *)launchOptions
{
    UIViewController *rootViewController = [[AppViewController alloc] init];
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = rootViewController;
    [self.window makeKeyAndVisible];
    return YES;
}

@end

#endif

//-----------------------------------------------------------------------------------
// Application main() function
//-----------------------------------------------------------------------------------

#if TARGET_OS_OSX

int main(int, const char**)
{
    @autoreleasepool
    {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

        AppDelegate *appDelegate = [[AppDelegate alloc] init];   // creates window
        [NSApp setDelegate:appDelegate];

        [NSApp activateIgnoringOtherApps:YES];
        [NSApp run];
    }
    return 0;
}

#else

int main(int argc, char * argv[])
{
    @autoreleasepool
    {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}

#endif
