//
//  EpubBookModel.m
//  XCEpubReader
//
//  Created by pro on 2016/9/23.
//  Copyright © 2016年 daisy. All rights reserved.
//

#import "EpubBookModel.h"
#import "ZipArchive.h"
#import "EpubChapterModel.h"
#import "XCReaderConst.h"
#import "ReaderConfig.h"
#import "GDataXMLNode.h"

typedef void(^ParseSuccessBlock)(BOOL finished, NSString * bookName);

@interface EpubBookModel ()
@property (nonatomic, readonly) NSString          * opfPath;
@property (nonatomic, readonly) NSString          * ncxPath;
@property (nonatomic, strong) NSString            * bookBasePath;
@property (nonatomic, copy)     ParseSuccessBlock   finishedBlock;
@property (nonatomic, copy) FirstChapterDidParseSuccess  firstChapterFinishedBlock;
@property (nonatomic, copy) LastChapterDidParseSuccess   lastChapterFinishedBlock;
@end


@implementation EpubBookModel
- (id)initWithEPubBookPath:(NSURL *)bookPath whenFirstChapterFinished:(void(^)(EpubBookModel *book))firstChacperFinished finalSuccess:(void(^)(EpubBookModel *book))success
{
    if((self = [super init])) {
        _bookPath                  = bookPath.path;
        NSString * lastPath        = [bookPath.path lastPathComponent];
        NSInteger loc2             = [lastPath rangeOfString:@"." options:NSBackwardsSearch].location;
        NSInteger len              = lastPath.length - loc2 + 1;
        _bookName                  = [lastPath substringWithRange:NSMakeRange(0, len)];
        _spineArray                = [[NSMutableArray alloc] init];
        _firstChapterFinishedBlock = firstChacperFinished;
        _lastChapterFinishedBlock  = success;
    }
    [self unzipBook];
    [self parseManifestFile];
    [self parseOPFFile];
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    if (self) {
        self.bookName            = [aDecoder decodeObjectForKey : @"bookName"];
        self.spineArray          = [aDecoder decodeObjectForKey : @"spineArray"];
        self.bookPath            = [aDecoder decodeObjectForKey : @"bookPath"];
        self.parseSucceed        = [aDecoder decodeBoolForKey   : @"parseSucceed"];
        self.recordModel         = [aDecoder decodeObjectForKey : @"recordModel"];
        self.currentChapterIndex = [aDecoder decodeIntegerForKey: @"ChapterIndex"];
        self.currentPageIndex    = [aDecoder decodeIntegerForKey: @"PageIndex"];
        
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject : self.bookName            forKey: @"bookName"];
    [aCoder encodeObject : self.spineArray          forKey: @"spineArray"];
    [aCoder encodeObject : self.bookPath            forKey: @"bookPath"];
    [aCoder encodeBool   : self.parseSucceed        forKey: @"parseSucceed"];
    [aCoder encodeObject : self.recordModel         forKey: @"recordModel"];
    [aCoder encodeInteger: self.currentPageIndex    forKey: @"PageIndex"];
    [aCoder encodeInteger: self.currentChapterIndex forKey: @"ChapterIndex"];
}

- (id)copyWithZone:(NSZone *)zone
{
    EpubBookModel *model      = [[EpubBookModel allocWithZone:zone] init];
    model.bookName            = self.bookName;
    model.bookPath            = self.bookPath;
    model.spineArray          = self.spineArray;
    model.parseSucceed        = self.parseSucceed;
    model.recordModel         = self.recordModel;
    model.currentPageIndex    = self.currentPageIndex;
    model.currentChapterIndex = self.currentChapterIndex;
    return model;
}

+ (void)updateLocalModel:(EpubBookModel *)readModel url:(NSURL *)url
{
    NSString      * key       = [url.path lastPathComponent];
    NSMutableData * data      = [[NSMutableData alloc]init];
    NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc]initForWritingWithMutableData:data];
    [archiver encodeObject: readModel forKey: key];
    [archiver finishEncoding];
    [[NSUserDefaults standardUserDefaults] setObject:data forKey:key];
}

+ (id)getLocalModelWithURL:(NSURL *)url;
{
    NSString * key            = [url.path lastPathComponent];
    NSData   * data           = [[NSUserDefaults standardUserDefaults] objectForKey: key];

    if (data) {
        NSLog(@"Local File Exist");
        NSKeyedUnarchiver * unarchive = [[NSKeyedUnarchiver alloc]initForReadingWithData:data];
        EpubBookModel     * model     = [unarchive decodeObjectForKey:key];
        model.bookPath                = url.path;
        if (model.parseSucceed) {
            return model;
        }
    }
    return nil;
}

+ (void)parseBookWithUrl:(NSURL *)url whenFirstChapterFinished:(void(^)(EpubBookModel *book))firstChacperFinished finalSuccess:(void(^)(EpubBookModel *book))success
{
    EpubBookModel * model = [[EpubBookModel alloc]initWithEPubBookPath:url whenFirstChapterFinished:firstChacperFinished finalSuccess:success];
    [EpubBookModel updateLocalModel:model url: url];
}

- (void)updateRecordeModel:(EpubRecordModel *)model withUrl:(NSURL *)url
{
    _recordModel = model;
    [[self class] updateLocalModel:self url: url];
}

#pragma mark - 解析电子书 -
- (BOOL)unzipBook
{
    ZipArchive * zipArchive = [[ZipArchive alloc] init];
    if( [zipArchive UnzipOpenFile: _bookPath]) {
        NSString * strPath  = [NSString stringWithFormat:@"%@/%@",kUserDocuments, self.bookName];
        if (![self isFileExist: strPath]) {
            BOOL ret        = [zipArchive UnzipFileTo:[NSString stringWithFormat:@"%@/",strPath] overWrite:YES];
            if( NO == ret ) {
                NSLog(@"解压失败");
            }
            [zipArchive UnzipCloseFile];
            
            return ret;
        } else {
            return YES;
        }
    }
    return NO;
}

- (void)parseManifestFile
{
    NSString *mainFestFilePath = [NSString stringWithFormat:@"%@/%@/META-INF/container.xml",kUserDocuments,self.bookName];
    if ([self isFileExist:mainFestFilePath]) {
        NSData *xmlData        = [[NSData alloc] initWithContentsOfFile:mainFestFilePath];
        GDataXMLDocument *doc  = [[GDataXMLDocument alloc] initWithData:xmlData error: nil];
        GDataXMLElement *root  = [doc rootElement];
        NSArray *nodes         = [root nodesForXPath:@"//@full-path[1]" error:nil];
        if ([nodes count]>0) {
            GDataXMLElement *opfNode = nodes[0];
            _opfPath = [NSString stringWithFormat:@"%@/%@/%@",kUserDocuments,self.bookName,[opfNode stringValue]];
        } else {
            _opfPath = nil;
            NSLog(@"解析 manifest 失败, 未找到opf路径节点");
        }
    }
}

- (void)parseOPFFile
{
    if (![self isFileExist:_opfPath]) {
        NSLog(@"OPF文件不存在!");
        return;
    }
    NSData *xmlData = [[NSData alloc] initWithContentsOfFile: self.opfPath];
    GDataXMLDocument * OPFXMLDoc  = [[GDataXMLDocument alloc] initWithData:xmlData error:nil];
    NSDictionary     * namespaces = [NSDictionary dictionaryWithObject:@"http://www.idpf.org/2007/opf" forKey:@"opf"];
    NSArray          * itemsArray = [OPFXMLDoc nodesForXPath:@"//opf:item" namespaces:namespaces error:nil];
    NSMutableDictionary * itemDic = [[NSMutableDictionary alloc] init];
    
    NSString * ncxFileName;
    for (GDataXMLElement *element in itemsArray) {
        
        [itemDic setValue:[[element attributeForName:@"href"] stringValue] forKey:[[element attributeForName:@"id"] stringValue]];
        NSString *mediaType = [[element attributeForName:@"media-type"] stringValue];
        if([mediaType isEqualToString:@"application/x-dtbncx+xml"]) {
            ncxFileName = [[element attributeForName:@"href"] stringValue];
        }
        
        if([mediaType isEqualToString:@"application/xhtml+xml"]) {
            ncxFileName = [[element attributeForName:@"href"] stringValue];
        }
    }
    
    NSInteger lastSlash           = [self.opfPath rangeOfString:@"/" options:NSBackwardsSearch].location;
    _bookBasePath                 = [self.opfPath substringToIndex:(lastSlash + 1)];
    _ncxPath                      = [NSString stringWithFormat:@"%@%@",_bookBasePath,ncxFileName];
    
    if (![self isFileExist:_ncxPath]) {
        NSLog(@"ncx文件不存在");
        return;
    }
    
    NSData *ncxPathUrl            = [[NSData alloc] initWithContentsOfFile: self.ncxPath];
    GDataXMLDocument    * ncxToc  = [[GDataXMLDocument alloc] initWithData:ncxPathUrl error:nil];
    
    NSMutableDictionary *titleDic = [[NSMutableDictionary alloc] init];
    for (GDataXMLElement*element in itemsArray) {
        NSString     * href       = [[element attributeForName:@"href"] stringValue];
        NSString     * xpath      = [NSString stringWithFormat:@"//ncx:content[@src='%@']/../ncx:navLabel/ncx:text", href];
        NSDictionary * namespace  = [NSDictionary dictionaryWithObject:@"http://www.daisy.org/z3986/2005/ncx/" forKey:@"ncx"];
        NSArray      * navPoints  = [ncxToc nodesForXPath:xpath namespaces: namespace error:nil];
        if([navPoints count] != 0)
        {
            GDataXMLElement * titleElement = [navPoints objectAtIndex:0];
            [titleDic setValue: [titleElement stringValue] forKey: href];
        }
    }
    
    NSArray        * itemRefsArray = [OPFXMLDoc nodesForXPath:@"//opf:itemref" namespaces:namespaces error:nil];
    int count = 0;
    for (GDataXMLElement *element in itemRefsArray)
    {
        NSString * chapHref        = [itemDic valueForKey: [[element attributeForName:@"idref"] stringValue]];
        NSString * spinePath       = [NSString stringWithFormat: @"%@%@", [self withoutDocumentsStr:_bookBasePath], chapHref];
        NSString * spineTitle      = [titleDic valueForKey: chapHref];
        EpubChapterModel *chapter  = [[EpubChapterModel alloc] init];
        [chapter setSpineIndex: count];
        [chapter setSpinePath: spinePath];
        [chapter setTitle: spineTitle];
        [_spineArray addObject:chapter];
        if (count == 0) {
            if (self.firstChapterFinishedBlock) {
                self.firstChapterFinishedBlock(self);
            }
        }
        count++;
    }
    
    _parseSucceed = self.spineArray.count > 0;
    if (self.lastChapterFinishedBlock) {
        self.lastChapterFinishedBlock(self);
    }
}


#pragma mark - Tool -
-(BOOL)isFileExist:(NSString *)path
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    return [fileManager fileExistsAtPath:path];
}
/** 去掉本地 Documents 文件路径 */
- (NSString *)withoutDocumentsStr:(NSString *)path
{
    return [path substringFromIndex:kUserDocuments.length];
}
@end
