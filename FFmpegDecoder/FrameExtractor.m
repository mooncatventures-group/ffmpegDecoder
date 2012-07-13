//
//  Video.m
//  iFrameExtractor
//
#import "FrameExtractor.h"
#include <libavformat/avformat.h>
#include <libswscale/swscale.h>


@interface FrameExtractor (private)


-(void)convertFrameToRGB;
-(UIImage *)imageFromAVPicture:(AVPicture)pict width:(int)width height:(int)height;
-(void)savePicture:(AVPicture)pFrame width:(int)width height:(int)height index:(int)iFrame;
- (CVPixelBufferRef) pixelBufferFromCGImage: (CGImageRef) image size:(CGSize) size;
-(CGImageRef)CGImageRefFromAVPicture:(AVPicture)pict width:(int)width height:(int)height;
-(CMSampleBufferRef)  cmSampleBufferFromCGImage: (CGImageRef) image size:(CGSize) size;


-(void)setupScaler;
@end

@implementation FrameExtractor
AVFormatContext *pFormatCtx;
AVCodecContext *pCodecCtx;
AVFrame *pFrame; 
AVPicture picture;
int videoStream;
struct SwsContext *img_convert_ctx;

@synthesize outputWidth, outputHeight;
@synthesize cgimageDelegate;
@synthesize pvpixelDelegate;
@synthesize cmsampleDelegate;


-(void)setOutputWidth:(int)newValue {
	if (outputWidth == newValue) return;
	outputWidth = newValue;
	[self setupScaler];
}

-(void)setOutputHeight:(int)newValue {
	if (outputHeight == newValue) return;
	outputHeight = newValue;
	[self setupScaler];
}

-(UIImage *)currentImage {
	if (!pFrame->data[0]) return nil;
	[self convertFrameToRGB];
	return [self imageFromAVPicture:picture width:outputWidth height:outputHeight];
}

-(CVPixelBufferRef)cvPixelBufferRef {
	if (!pFrame->data[0]) return nil;
	[self convertFrameToRGB];
    CGImageRef cgImage = [self CGImageRefFromAVPicture:picture width:outputWidth height:outputHeight];
    return [self pixelBufferFromCGImage:cgImage size:CGSizeMake(outputWidth, outputHeight)];
    
}

-(CMSampleBufferRef)cmSampleBufferRef {
	if (!pFrame->data[0]) return nil;
	[self convertFrameToRGB];
    CGImageRef cgImage = [self CGImageRefFromAVPicture:picture width:outputWidth height:outputHeight];
    return [self cmSampleBufferFromCGImage:cgImage size:CGSizeMake(outputWidth, outputHeight)];
    
}



-(double)duration {
	return (double)pFormatCtx->duration / AV_TIME_BASE;
}

-(int)sourceWidth {
	return pCodecCtx->width;
}

-(int)sourceHeight {
	return pCodecCtx->height;
}

-(id)initWithVideo:(NSString *)moviePath {
	if (!(self=[super init])) return nil;
    
    AVCodec         *pCodec;
    
    // Register all formats and codecs
    avcodec_register_all();
	av_register_all();
        
	
    // Open video file
       

    
  //  if(av_open_input_file(&pFormatCtx, "rtsp://a2047.v1412b.c1412.g.vq.akamaistream.net/5/2047/1412/1_h264_350/1a1a1ae555c531960166d//f4dbc3095c327960d7be756b71b49aa1576e344addb3ead1a497aaedf11/8848125_1_350.mov", NULL, 0, NULL)!=0)
       // goto initError; // Couldn't open file
    
    if(av_open_input_file(&pFormatCtx, [moviePath UTF8String], NULL, 0, NULL)!=0)
        goto initError; // Couldn't open file

	
    // Retrieve stream information
    if(av_find_stream_info(pFormatCtx)<0)
        goto initError; // Couldn't find stream information
    
    // Find the first video stream
    videoStream=-1;
    for(int i=0; i<pFormatCtx->nb_streams; i++)
        if(pFormatCtx->streams[i]->codec->codec_type==AVMEDIA_TYPE_VIDEO)
        {
            videoStream=i;
            break;
        }
    if(videoStream==-1)
        goto initError; // Didn't find a video stream
	
    // Get a pointer to the codec context for the video stream
    pCodecCtx=pFormatCtx->streams[videoStream]->codec;
    
    // Find the decoder for the video stream
    pCodec=avcodec_find_decoder(pCodecCtx->codec_id);
    if(pCodec==NULL)
        goto initError; // Codec not found
	
    // Open codec
    if(avcodec_open(pCodecCtx, pCodec)<0)
        goto initError; // Could not open codec
	
    // Allocate video frame
    pFrame=avcodec_alloc_frame();
    
	outputWidth = pCodecCtx->width;
	self.outputHeight = pCodecCtx->height;
    
	return self;
	
initError:
	[self release];
    NSLog(@"an error occurred");
	return nil;
}


-(void)setupScaler {
    
	// Release old picture and scaler
	avpicture_free(&picture);
	sws_freeContext(img_convert_ctx);	
	
	// Allocate RGB picture
	avpicture_alloc(&picture, PIX_FMT_RGB24, outputWidth, outputHeight);
	
	// Setup scaler
	static int sws_flags =  SWS_FAST_BILINEAR;
	img_convert_ctx = sws_getContext(pCodecCtx->width, 
									 pCodecCtx->height,
									 pCodecCtx->pix_fmt,
									 outputWidth, 
									 outputHeight,
									 PIX_FMT_RGB24,
									 sws_flags, NULL, NULL, NULL);
	
}

-(void)seekTime:(double)seconds {
	AVRational timeBase = pFormatCtx->streams[videoStream]->time_base;
	int64_t targetFrame = (int64_t)((double)timeBase.den / timeBase.num * seconds);
	avformat_seek_file(pFormatCtx, videoStream, targetFrame, targetFrame, targetFrame, AVSEEK_FLAG_FRAME);
	avcodec_flush_buffers(pCodecCtx);
}

-(void)dealloc {
	// Free scaler
	sws_freeContext(img_convert_ctx);	
    
	// Free RGB picture
	avpicture_free(&picture);
	
    // Free the YUV frame
    av_free(pFrame);
	
    // Close the codec
    if (pCodecCtx) avcodec_close(pCodecCtx);
	
    // Close the video file
    if (pFormatCtx) av_close_input_file(pFormatCtx);
	
	[super dealloc];
}

-(BOOL)stepFrame {
	AVPacket packet;
    int frameFinished=0;
    
    while(!frameFinished && av_read_frame(pFormatCtx, &packet)>=0) {
        // Is this a packet from the video stream?
        if(packet.stream_index==videoStream) {
            // Decode video frame
            avcodec_decode_video2(pCodecCtx, pFrame, &frameFinished, &packet);
        }
		
        // Free the packet that was allocated by av_read_frame
        av_free_packet(&packet);
	}
	return frameFinished!=0;
}

-(void)convertFrameToRGB {	
	sws_scale (img_convert_ctx, pFrame->data, pFrame->linesize,
			   0, pCodecCtx->height,
			   picture.data, picture.linesize);	
}

-(UIImage *)imageFromAVPicture:(AVPicture)pict width:(int)width height:(int)height {
	CGBitmapInfo bitmapInfo = kCGBitmapByteOrderDefault;
	CFDataRef data = CFDataCreateWithBytesNoCopy(kCFAllocatorDefault, pict.data[0], pict.linesize[0]*height,kCFAllocatorNull);
	CGDataProviderRef provider = CGDataProviderCreateWithCFData(data);
	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
	CGImageRef cgImage = CGImageCreate(width, 
									   height, 
									   8, 
									   24, 
									   pict.linesize[0], 
									   colorSpace, 
									   bitmapInfo, 
									   provider, 
									   NULL, 
									   NO, 
									   kCGRenderingIntentDefault);
	CGColorSpaceRelease(colorSpace);
	UIImage *image = [UIImage imageWithCGImage:cgImage];
	CGImageRelease(cgImage);
	CGDataProviderRelease(provider);
	CFRelease(data);
	
	return image;
}

-(CGImageRef)CGImageRefFromAVPicture:(AVPicture)pict width:(int)width height:(int)height {
	CGBitmapInfo bitmapInfo = kCGBitmapByteOrderDefault;
	CFDataRef data = CFDataCreateWithBytesNoCopy(kCFAllocatorDefault, pict.data[0], pict.linesize[0]*height,kCFAllocatorNull);
	CGDataProviderRef provider = CGDataProviderCreateWithCFData(data);
	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
	CGImageRef cgImage = CGImageCreate(width, 
									   height, 
									   8, 
									   24, 
									   pict.linesize[0], 
									   colorSpace, 
									   bitmapInfo, 
									   provider, 
									   NULL, 
									   NO, 
									   kCGRenderingIntentDefault);
		return cgImage;
}


- (CVPixelBufferRef) pixelBufferFromCGImage: (CGImageRef) image size:(CGSize) size
{
    NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
							 [NSNumber numberWithBool:YES], kCVPixelBufferCGImageCompatibilityKey,
							 [NSNumber numberWithBool:YES], kCVPixelBufferCGBitmapContextCompatibilityKey,
							 nil];
    CVPixelBufferRef pxbuffer = NULL;
    
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault, size.width,
										  size.height, kCVPixelFormatType_32ARGB, (CFDictionaryRef) options,
										  &pxbuffer);
    NSParameterAssert(status == kCVReturnSuccess && pxbuffer != NULL);
    
    CVPixelBufferLockBaseAddress(pxbuffer, 0);
    void *pxdata = CVPixelBufferGetBaseAddress(pxbuffer);
    NSParameterAssert(pxdata != NULL);
    
    CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pxdata, size.width,
												 size.height, 8, 4*size.width, rgbColorSpace,
												 kCGImageAlphaNoneSkipFirst);
    NSParameterAssert(context);
    CGContextConcatCTM(context, CGAffineTransformMakeRotation(0));
    CGContextDrawImage(context, CGRectMake(0, 0, CGImageGetWidth(image),
										   CGImageGetHeight(image)), image);
    CGColorSpaceRelease(rgbColorSpace);
    CGContextRelease(context);
    
    CVPixelBufferUnlockBaseAddress(pxbuffer, 0);
    
    return pxbuffer;
}

- (CMSampleBufferRef)  cmSampleBufferFromCGImage: (CGImageRef) image size:(CGSize) size
{
    NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
							 [NSNumber numberWithBool:YES], kCVPixelBufferCGImageCompatibilityKey,
							 [NSNumber numberWithBool:YES], kCVPixelBufferCGBitmapContextCompatibilityKey,
							 nil];
    CVPixelBufferRef pxbuffer = NULL;
    
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault, size.width,
										  size.height, kCVPixelFormatType_32ARGB, (CFDictionaryRef) options,
										  &pxbuffer);
    NSParameterAssert(status == kCVReturnSuccess && pxbuffer != NULL);
    
    CVPixelBufferLockBaseAddress(pxbuffer, 0);
    void *pxdata = CVPixelBufferGetBaseAddress(pxbuffer);
    NSParameterAssert(pxdata != NULL);
    
    CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pxdata, size.width,
												 size.height, 8, 4*size.width, rgbColorSpace,
												 kCGImageAlphaNoneSkipFirst);
    NSParameterAssert(context);
    CGContextConcatCTM(context, CGAffineTransformMakeRotation(0));
    CGContextDrawImage(context, CGRectMake(0, 0, CGImageGetWidth(image),
										   CGImageGetHeight(image)), image);
    CGColorSpaceRelease(rgbColorSpace);
    CGContextRelease(context);
    CVPixelBufferUnlockBaseAddress(pxbuffer, 0);
    CMVideoFormatDescriptionRef videoInfo = NULL;
    CMSampleBufferRef sampleBuffer = NULL;
    CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault,
                                                pxbuffer, true, NULL, NULL, videoInfo, NULL, &sampleBuffer);
    return sampleBuffer;
}




-(void)setupCgimageSession {
	lastFrameTime = -1;
	
	// seek to 0.0 seconds
	[self seekTime:0.0];
    NSLog(@"setting timer");
	[NSTimer scheduledTimerWithTimeInterval:kPollingInterval 
									 target:self
								   selector:@selector(displayNextImageBuffer:)
								   userInfo:nil
									repeats:YES];
}

-(void)displayNextImageBuffer:(NSTimer *)timer {
    [cgimageDelegate didOutputCGImageBuffer:timer];
}

-(void)setupPVimageSession {
	lastFrameTime = -1;
	
	// seek to 0.0 seconds
	[self seekTime:0.0];
    
	[NSTimer scheduledTimerWithTimeInterval:kPollingInterval 
									 target:self
								   selector:@selector(displayNextPVBuffer:)
								   userInfo:nil
									repeats:YES];
}

-(void)displayNextPVBuffer:(NSTimer *)timer {
    [pvpixelDelegate didOutputPixelBuffer:timer];
}

-(void)setupCmsampleSession {
	lastFrameTime = -1;
	
	// seek to 0.0 seconds
	[self seekTime:0.0];
    
	[NSTimer scheduledTimerWithTimeInterval:kPollingInterval 
									 target:self
								   selector:@selector(displayNextCMSampleBuffer:)
								   userInfo:nil
									repeats:YES];
}

-(void)displayNextCMSampleBuffer:(NSTimer *)timer {
    [cmsampleDelegate didOutputSampleBuffer:timer];
}







@end
