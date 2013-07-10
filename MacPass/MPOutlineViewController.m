//
//  MPOutlineViewController.m
//  MacPass
//
//  Created by michael starke on 19.02.13.
//  Copyright (c) 2013 HicknHack Software GmbH. All rights reserved.
//

#import "MPOutlineViewController.h"
#import "MPOutlineDataSource.h"
#import "MPDocument.h"
#import "MPDocumentWindowController.h"
#import "MPContextMenuHelper.h"
#import "MPConstants.h"
#import "MPActionHelper.h"
#import "MPIconHelper.h"
#import "MPUppercaseStringValueTransformer.h"
#import "MPRootAdapter.h"

#import "KdbLib.h"
#import "Kdb4Node.h"
#import "KdbGroup+Undo.h"

#import "HNHGradientView.h"

NSString *const MPOutlineViewDidChangeGroupSelection = @"com.macpass.MPOutlineViewDidChangeGroupSelection";

NSString *const _MPOutlineViewDataViewIdentifier = @"DataCell";
NSString *const _MPOutlinveViewHeaderViewIdentifier = @"HeaderCell";

@interface MPOutlineViewController () {
  BOOL _bindingEstablished;
}
@property (weak) IBOutlet NSOutlineView *outlineView;
@property (weak) IBOutlet NSButton *addGroupButton;
@property (weak) KdbGroup *selectedGroup;

@property (strong) NSTreeController *treeController;
@property (strong) MPOutlineDataSource *datasource;
@property (strong) NSMenu *menu;

@property (copy, nonatomic) NSString *databaseNameWrapper;

@end

@implementation MPOutlineViewController

- (id)init {
  return [[MPOutlineViewController alloc] initWithNibName:@"OutlineView" bundle:nil];
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
  self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
  if (self) {
    _treeController = [[NSTreeController alloc] init];
    _bindingEstablished = NO;
    _datasource = [[MPOutlineDataSource alloc] init];
    _databaseNameWrapper = NSLocalizedString(@"NEW_DATABASE", "Name for a newly created Database");
  }
  
  return self;
}


- (void)didLoadView {
  [_outlineView setDelegate:self];
  [_outlineView setMenu:[self _contextMenu]];
  [_outlineView setAllowsEmptySelection:YES];
  [_outlineView setFloatsGroupRows:NO];
  //[_outlineView registerForDraggedTypes:@[ MPPasteBoardType ]];
  [_outlineView setDraggingSourceOperationMask:NSDragOperationEvery forLocal:YES];
  [_bottomBar setBorderType:HNHBorderTop];
  [_addGroupButton setAction:[MPActionHelper actionOfType:MPActionAddGroup]];
}

- (void)showOutline {
  if(!_bindingEstablished) {
    MPDocument *document = [[self windowController] document];
    [_treeController setChildrenKeyPath:@"groups"];
    [_treeController bind:NSContentBinding toObject:document withKeyPath:@"rootAdapter" options:nil];
    [_outlineView bind:NSContentBinding toObject:_treeController withKeyPath:@"arrangedObjects" options:nil];
    if([document.tree respondsToSelector:@selector(databaseName)]) {
      [self bind:@"databaseNameWrapper" toObject:document.tree withKeyPath:@"databaseName" options:nil];
    }
    [_outlineView setDataSource:self.datasource];
    _bindingEstablished = YES;
  }
  NSTreeNode *node = [_outlineView itemAtRow:0];
  [_outlineView expandItem:node expandChildren:YES];
}

#pragma mark Notifications
- (void)setupNotifications:(MPDocumentWindowController *)windowController {
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_didCreateGroup:) name:MPDocumentDidAddGroupNotification object:[windowController document]];
}

- (void)clearSelection {
  [_outlineView deselectAll:nil];
  [self outlineViewSelectionDidChange:nil];
}

- (void)_didCreateGroup:(NSNotification *)notification {
  NSInteger selectedRow = [_outlineView selectedRow];
  NSIndexSet *indexSet;
  if( selectedRow == -1) {
    MPDocument *document = [[self windowController] document];
    indexSet = [NSIndexSet indexSetWithIndex:[document.root.groups count]];
    //TODO: Find out why selection is not set (treeUpdate?)
  }
  else {
    id item = [_outlineView itemAtRow:selectedRow];
    [_outlineView expandItem:item];
    indexSet = [NSIndexSet indexSetWithIndex:selectedRow + 1];
  }
}

- (void)setDatabaseNameWrapper:(NSString *)databaseNameWrapper {
  if(![_databaseNameWrapper isEqualToString:databaseNameWrapper]) {
    if([databaseNameWrapper length] == 0) {
      _databaseNameWrapper = NSLocalizedString(@"DATABASE", "Default name database");
    }
    else {
      _databaseNameWrapper= [databaseNameWrapper copy];
    }
  }
}

#pragma mark -
#pragma mark Actions

- (void)createGroup:(id)sender {
  KdbGroup *group = [self _clickedOrSelectedGroup];
  MPDocument *document = [[self windowController] document];
  if(!group) {
    group = document.root;
  }
  [document createGroup:group];
}

- (void)createEntry:(id)sender {
  MPDocument *document = [[self windowController] document];
  [document createEntry:[self _clickedOrSelectedGroup]];
}

- (void)deleteNode:(id)sender {
  [[[self windowController] document] deleteGroup:[self _clickedOrSelectedGroup]];
}

#pragma mark NSOutlineViewDelegate
- (NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)tableColumn item:(id)item {
  NSTableCellView *view;
  if( [self _itemIsRootNodeAdapter:item] ) {
    //NSDictionary *options = @{ NSValueTransformerBindingOption : [NSValueTransformer valueTransformerForName:MPUppsercaseStringValueTransformerName] };
    view = [outlineView makeViewWithIdentifier:_MPOutlinveViewHeaderViewIdentifier owner:self];
    [view.textField bind:NSValueBinding toObject:self  withKeyPath:@"databaseNameWrapper" options:nil];
  }
  else {
    KdbGroup *group = [item representedObject];
    view = [outlineView makeViewWithIdentifier:_MPOutlineViewDataViewIdentifier owner:self];
    NSImage *icon = [MPIconHelper icon:(MPIconType)[group image]];
    [view.imageView setImage:icon];
    [view.textField bind:NSValueBinding toObject:group withKeyPath:MPGroupNameUndoableKey options:nil];
    [view.textField bind:@"count" toObject:group withKeyPath:@"entries.@count" options:nil];
  }
  
  return view;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isGroupItem:(id)item {
  return [self _itemIsRootNodeAdapter:item];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item {
  return ![self _itemIsRootNodeAdapter:item];
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
  NSTreeNode *treeNode = [_outlineView itemAtRow:[_outlineView selectedRow]];
  KdbGroup *selectedGroup = [treeNode representedObject];
  self.selectedGroup = selectedGroup;
  [[NSNotificationCenter defaultCenter] postNotificationName:MPOutlineViewDidChangeGroupSelection object:self userInfo:nil];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldShowOutlineCellForItem:(id)item {
  return ![self _itemIsRootNodeAdapter:item];
}

#pragma mark -
#pragma mark Private

- (KdbGroup *)_clickedOrSelectedGroup {
  NSInteger row = [self.outlineView clickedRow];
  if( row < 0 ) {
    row = [self.outlineView selectedRow];
  }
  return [[self.outlineView itemAtRow:row] representedObject];
}

- (NSMenu *)_contextMenu {
  NSMenu *menu = [[NSMenu alloc] init];
  NSArray *items = [MPContextMenuHelper contextMenuItemsWithItems:MPContextMenuMinimal];
  for(NSMenuItem *item in items) {
    [menu addItem:item];
  }
  return menu;
}

- (BOOL)_itemIsRootNodeAdapter:(id)item {
  id node = [item representedObject];
  return [node isKindOfClass:[MPRootAdapter class]];
}

@end
