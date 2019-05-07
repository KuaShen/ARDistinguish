//
//  DIViewController.m
//  ARDistinguish
//
//  Created by KuaShen on 03/28/2019.
//  Copyright (c) 2019 KuaShen. All rights reserved.
//

#import <ARKit/ARKit.h>
#import "DIViewController.h"
#import <SceneKit/SceneKit.h>
#import "UIFont+DIExtension.h"
#import "Inceptionv3.h"
#import <CommonCrypto/CommonDigest.h>
#import "AFNetworking/AFNetworking.h"

#import <Vision/Vision.h>

#define SCREEN_W ([[UIScreen mainScreen] bounds].size.width)
#define SCREEN_H ([[UIScreen mainScreen] bounds].size.height)

#define kBaiduTranslationAPPID @"20190430000292904"
#define kBaiduTranslationSalt @"1435660288"
#define kBaiduTranslationKey @"3yE6R_KmCb6RVd8uXIjR"

@interface DIViewController ()<ARSCNViewDelegate>{
    
    NSString *latestPrediction;
    CGFloat bubbleDepth;
    NSArray <VNRequest *>*visionRequests;
    dispatch_queue_t dispatchQueueML;
    SCNVector3 minBound;
    SCNVector3 maxBound;
    SCNVector3 worldCoord;
}

@property (nonatomic, strong) ARSCNView *sceneView;

@property (nonatomic, strong) ARSession *session;

@property (nonatomic, strong) ARWorldTrackingConfiguration *trackConfig;

@property (nonatomic, strong) UITextView *debugTextView;
@property (nonatomic, strong) UIImageView *centerImage;

@end

@implementation DIViewController{
    NSString *resStr;
    NSString *debugText;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self startAR];
    [self setUI];
    [self initData];
    [self tryCoreMLDistinguish];
}

- (void)startAR{
    
    self.view = self.sceneView;
    _sceneView.delegate = self;
    _sceneView.session = self.session;
    
}

- (void)setUI{
    
//    [self.sceneView addSubview:self.debugTextView];
    [self.sceneView addSubview:self.centerImage];
    
}

- (void)initData{
    latestPrediction = @"测试";
    bubbleDepth = .1;
    dispatchQueueML = dispatch_queue_create("vergil", NULL);
    minBound = SCNVector3Zero;
    maxBound = SCNVector3Zero;
}


- (void)viewWillAppear:(BOOL)animated{
    [super viewWillAppear:YES];
    
    [_session runWithConfiguration:self.trackConfig options:nil];
    
}
- (void)viewWillDisappear:(BOOL)animated{
    
    [_session pause];
}

- (void)tryCoreMLDistinguish{
    Inceptionv3 *modelFile = [[Inceptionv3 alloc]init];
    VNCoreMLModel *model = [VNCoreMLModel modelForMLModel:modelFile.model error:nil];
    
    VNCoreMLRequest *classificationRequest = [[VNCoreMLRequest alloc]initWithModel:model completionHandler:^(VNRequest * _Nonnull request, NSError * _Nullable error) {
        [self classificationCompletionHandler:request error:error];
    }];
    classificationRequest.imageCropAndScaleOption = VNImageCropAndScaleOptionCenterCrop;
    visionRequests = @[classificationRequest];
    
    //循环识别
    [self loopCoreMLUpdate];
}


- (void)loopCoreMLUpdate{
    dispatch_async(dispatchQueueML, ^{
        [self updateCoreML];
        [self loopCoreMLUpdate];
    });
}

- (void)updateCoreML{
    CVPixelBufferRef pixbuff = _sceneView.session.currentFrame.capturedImage;
    if (pixbuff == nil) {
        return;
    }
    
//    CIImage *ciImage = [CIImage imageWithCVImageBuffer:pixbuff];
//    VNImageRequestHandler *imageRequestHandler = [[VNImageRequestHandler alloc]initWithCIImage:ciImage options:nil];
    VNImageRequestHandler *imageRequestHandler = [[VNImageRequestHandler alloc]initWithCVPixelBuffer:pixbuff options:nil];
    
    @try {
        [imageRequestHandler performRequests:visionRequests error:nil];
    } @catch (NSException *exception) {
        NSLog(@"%@",exception);
    } @finally {
        
    }
}

- (void)classificationCompletionHandler:(VNRequest *)request error:(NSError *)error{
    if (error) {
        NSLog(@"%@",error.localizedDescription);
    }
    NSArray <VNClassificationObservation *>*observations;
    if (request.results.count > 0) {
        observations = request.results;
    }else
        return;
    NSArray <VNClassificationObservation *>*classifications = [observations subarrayWithRange:NSMakeRange(0, 1)];
    NSMutableArray *resultArray = [NSMutableArray array];
    for (VNClassificationObservation *classification in classifications) {
        [resultArray addObject:[NSString stringWithFormat:@"%@ - %.2f\n",classification.identifier,classification.confidence]];
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        
        
        for (NSString *string in resultArray) {
            [debugText stringByAppendingString:string];
        }
        self.debugTextView.text = debugText;
        
        latestPrediction = [self translateToChinese:classifications[0].identifier];
        
//        latestPrediction = @"哈哈";
//        NSString *objectName = @"";
//        objectName = [classifications componentsJoinedByString:@"-"];
//        objectName = [objectName componentsSeparatedByString:@","][0];
//        latestPrediction = objectName;
    });
    
}

- (NSString *)translateToChinese:(NSString *)en{
    //百度API
    NSString *httpStr = @"https://fanyi-api.baidu.com/api/trans/vip/translate";
    //将APPID q salt key 拼接一起
    NSString *appendStr = [NSString stringWithFormat:@"%@%@%@%@",kBaiduTranslationAPPID,en,kBaiduTranslationSalt,kBaiduTranslationKey];
    //加密 生成签名
    NSString *md5Str = [self md5:appendStr];
    //将待翻译的文字机型urf-8转码
    NSString *qEncoding = [en stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    //使用get请求
    
    NSString *urlStr = [NSString stringWithFormat:@"%@?q=%@&from=%@&to=%@&appid=%@&salt=%@&sign=%@",httpStr,qEncoding,@"auto",@"zh",kBaiduTranslationAPPID,kBaiduTranslationSalt,md5Str];
    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
    //添加共有参数
    
    [manager.requestSerializer willChangeValueForKey:@"timeoutInterval"];
    manager.requestSerializer.timeoutInterval = 20.f;
    [manager.requestSerializer didChangeValueForKey:@"timeoutInterval"];
    
    [manager GET:urlStr parameters:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        
        if (responseObject == nil) {
            return ;
            
        }
        //获取翻译后的字符串
        resStr = [[responseObject objectForKey:@"trans_result"] firstObject][@"dst"];
        
        
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        
    }];
    
    
    return resStr;
}

- (NSString *) md5:(NSString *) str
{
    const char *cStr = [str UTF8String];
    unsigned char result[16];
    CC_MD5(cStr, strlen(cStr), result); // This is the md5 call
    return [NSString stringWithFormat:
            @"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
            result[0], result[1], result[2], result[3],
            result[4], result[5], result[6], result[7],
            result[8], result[9], result[10], result[11],
            result[12], result[13], result[14], result[15]
            ];
}

- (void)handleTap:(UITapGestureRecognizer *)tap{
    CGPoint screenCenter = CGPointMake(_sceneView.center.x, _sceneView.center.y);
    NSArray <ARHitTestResult *>*arHitResults = [_sceneView hitTest:screenCenter types:(ARHitTestResultTypeFeaturePoint)];
    ARHitTestResult *closestResult = [arHitResults firstObject];
    if (closestResult) {
        matrix_float4x4 transform = closestResult.worldTransform;
        worldCoord = SCNVector3Make(transform.columns[3].x, transform.columns[3].y, transform.columns[3].z);
        //创建3D文字
        SCNNode *textNode = [self createNewBubbleParentNodeWithText:latestPrediction];
        [_sceneView.scene.rootNode addChildNode:textNode];
        textNode.position = worldCoord;
        NSLog(@"textNode = %@,   childOne = = %@,     childTwo == == == %@",textNode,textNode.childNodes[0],textNode.childNodes[1]);
        
    }
    
}

- (SCNNode *)createNewBubbleParentNodeWithText:(NSString *)text{
    
    SCNBillboardConstraint *billboardConstraint = [SCNBillboardConstraint billboardConstraint];
    billboardConstraint.freeAxes = SCNBillboardAxisY;
    
    SCNText *bubble = [SCNText textWithString:text extrusionDepth:bubbleDepth];
    UIFont *font = [UIFont fontWithName:@"Futura" size:.15];
    font = [UIFont fontWithTraits:(UIFontDescriptorTraitBold)];
    bubble.font = font;
    bubble.alignmentMode = kCAAlignmentCenter;
    bubble.firstMaterial.diffuse.contents = [UIColor orangeColor];
//    bubble.firstMaterial.specular.contents = [UIColor whiteColor];
//    [bubble.firstMaterial setDoubleSided:YES];
    bubble.chamferRadius = bubbleDepth;
    
    SCNNode *bubbleNode = [SCNNode nodeWithGeometry:bubble];
    [bubbleNode getBoundingBoxMin:&minBound max:&maxBound];
    bubbleNode.pivot = SCNMatrix4MakeTranslation((maxBound.x - minBound.x)/2, minBound.y, bubbleDepth/2);
    bubbleNode.scale = SCNVector3Make(.002, .002, .002);
    NSLog(@"text = %@,node = =%@,",bubble, bubbleNode);
    
    SCNSphere *sphere = [SCNSphere sphereWithRadius:0.005];
    sphere.firstMaterial.diffuse.contents = [UIColor cyanColor];
    SCNNode *sphereNode = [SCNNode nodeWithGeometry:sphere];
    
    SCNNode *bubbleNodeParent = [SCNNode node];
    [bubbleNodeParent addChildNode:bubbleNode];
    [bubbleNodeParent addChildNode:sphereNode];
    bubbleNodeParent.constraints = @[billboardConstraint];
    
    return bubbleNodeParent;
}


#pragma mark ------------ lazy load -------------

- (ARSCNView *)sceneView API_AVAILABLE(ios(11.0)){
    if (!_sceneView){
        if (@available(iOS 11.0, *)) {
            _sceneView = [[ARSCNView alloc] init];
            _sceneView.frame = self.view.bounds;
            
            UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(handleTap:)];
            [_sceneView addGestureRecognizer:tap];
        }
        
    }
    
    
    return _sceneView;
}

- (ARSession *)session API_AVAILABLE(ios(11.0)){
    if (!_session){
        if (@available(iOS 11.0, *)) {
            _session = [[ARSession alloc] init];
            
        }
        
    }
    
    
    return _session;
}

- (ARWorldTrackingConfiguration *)trackConfig API_AVAILABLE(ios(11.0)){
    if (!_trackConfig) {
        //创建追踪
        if (@available(iOS 11.0, *)) {
            ARWorldTrackingConfiguration *configuration = [[ARWorldTrackingConfiguration alloc]init];
            configuration.planeDetection = ARPlaneDetectionHorizontal;
            
            //自适应灯光(有强光到弱光会变的平滑一些)
            _trackConfig = configuration;
            _trackConfig.lightEstimationEnabled = true;
            
            [_session runWithConfiguration:configuration];
        }
        
    }
    
    return _trackConfig;
}

- (UITextView *)debugTextView{
    if (!_debugTextView){
        _debugTextView = [[UITextView alloc] init];
        _debugTextView.frame = CGRectMake(0, 0, SCREEN_W, 150);
        _debugTextView.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:.5];
    }
    
    return _debugTextView;
}

- (UIImageView *)centerImage{
    if (!_centerImage){
        _centerImage = [[UIImageView alloc] init];
        _centerImage.frame = CGRectMake(SCREEN_W / 2 - 20, SCREEN_H / 2 - 20, 40, 40);
        _centerImage.image = [UIImage imageNamed:@"center"];
    }
    
    
    return _centerImage;
}

@end
