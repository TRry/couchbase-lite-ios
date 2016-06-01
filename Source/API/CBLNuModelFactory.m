//
//  CBLNuModelFactory.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 8/18/14.
//
//

#import "CBLNuModelFactory.h"
#import "CBLObject_Internal.h"
#import "CBLCache.h"


// Extend CBLNuModel to allow instances to be stored in a CBLCache.
@interface CBLNuModel (Cacheable) <CBLCacheable>
@end

@implementation CBLNuModel (Cacheable)
- (NSString*) cacheKey {
    return self.documentID;
}
@end




@implementation CBLNuModelFactory
{
    CBLCache* _cache;
    NSMutableDictionary* _types;
}


@synthesize delegate=_delegate, unsavedModels=_unsavedModels;


- (instancetype) init {
    self = [super init];
    if (self) {
        _cache = [[CBLCache alloc] initWithRetainLimit: 20];
        _unsavedModels = [[NSMutableSet alloc] init];
    }
    return self;
}


- (void) registerModelClass: (Class)modelClass {
    Assert([modelClass isSubclassOfClass: [CBLNuModel class]]);
    NSArray* types = [modelClass documentTypes];
    Assert(types.count > 0, @"Model class %@ has no registered document types; override +documentTypes", modelClass);
    if (!_types)
        _types = [NSMutableDictionary new];
    for (NSString* type in types) {
        Assert(!_types[type], @"Conflict: document type '%@' is claimed by both %@ and %@",
               _types[type], modelClass);
        _types[type] = modelClass;
    }
}

- (Class) modelClassForDocumentType: (NSString*)docType {
    return docType ? _types[docType] : nil;
}


- (CBLNuModel*) modelWithDocumentID: (NSString*)documentID
                            ofClass: (Class)ofClass
                     readProperties: (BOOL)readProperties
                              error: (NSError**)outError
{
    CBLNuModel* model = [_cache resourceWithCacheKey: documentID];
    if (!model) {
        model = [[ofClass alloc] initWithFactory: self documentID: documentID];
        if (!model)
            return nil;
        if (readProperties) {
            if (![self readPropertiesOfModel: model error: outError])
                return nil;
            [_cache addResource: model];
            [model awakeFromFetch];
        } else {
            [_cache addResource: model];
            [model turnIntoFault];
        }
    }
    Assert(!ofClass || model.isFault || [model isKindOfClass: ofClass],
           @"Asked for model of doc %@ as a %@, but it's already instantiated as a %@",
           documentID, ofClass, [model class]);
    return model;
}


- (CBLNuModel*) availableModelWithDocumentID: (NSString*)documentID {
    return [_cache resourceWithCacheKey: documentID];
}


- (void) addModel: (CBLNuModel*)model {
    AssertNil(model.factory);
    model.factory = self;
    [_unsavedModels addObject: model];
    [_cache addResource: model];
}


- (BOOL) saveAllModels: (NSError**)outError {
    if (_unsavedModels.count == 0)
        return YES;
    id<CBLNuModelFactoryDelegate> delegate = _delegate;
    Assert(delegate);
    return [delegate savePropertiesOfModels: [_unsavedModels copy] error: outError];
}

- (BOOL) autosaveAllModels: (NSError**)outError {
    NSMutableSet* autosaveModels = nil;
    for (CBLNuModel* model in _unsavedModels) {
        if (model.autosaves) {
            if (!autosaveModels)
                autosaveModels = [[NSMutableSet alloc] initWithCapacity: _unsavedModels.count];
            [autosaveModels addObject: model];
        }
    }
    if (!autosaveModels)
        return YES;

    id<CBLNuModelFactoryDelegate> delegate = _delegate;
    Assert(delegate);
    return [delegate savePropertiesOfModels: autosaveModels error: outError];
}

- (BOOL) readPropertiesOfModel: (CBLNuModel*)model error: (NSError**)error {
    id<CBLNuModelFactoryDelegate> delegate = _delegate;
    Assert(delegate);
    return [delegate readPropertiesOfModel: model error: error];
}

- (BOOL) savePropertiesOfModel: (CBLNuModel*)model error: (NSError**)error {
    id<CBLNuModelFactoryDelegate> delegate = _delegate;
    Assert(delegate);
    return [delegate savePropertiesOfModel: model error: error];
}


@end
