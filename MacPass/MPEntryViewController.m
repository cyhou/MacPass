//
//  MPEntryViewController.m
//  MacPass
//
//  Created by michael starke on 18.02.13.
//  Copyright (c) 2013 HicknHack Software GmbH. All rights reserved.
//

#import "MPEntryViewController.h"
#import "MPAppDelegate.h"
#import "MPOutlineViewController.h"
#import "MPDocument.h"
#import "MPIconHelper.h"
#import "MPDocumentWindowController.h"
#import "MPPasteBoardController.h"
#import "MPOverlayWindowController.h"

#import "MPContextMenuHelper.h"
#import "MPActionHelper.h"
#import "MPConstants.h"
#import "MPEntryTableDataSource.h"
#import "MPStringLengthValueTransformer.h"

#import "HNHTableHeaderCell.h"
#import "HNHGradientView.h"

#import "KdbGroup+MPTreeTools.h"
#import "KdbGroup+Undo.h"
#import "KdbEntry+Undo.h"

NSString *const MPDidChangeSelectedEntryNotification = @"com.macpass.MPDidChangeSelectedEntryNotification";

#define STATUS_BAR_ANIMATION_TIME 0.2

typedef NS_OPTIONS(NSUInteger, MPFilterModeType) {
  MPFilterNone      = 0,
  MPFilterUrls      = (1<<0),
  MPFilterUsernames = (1<<1),
  MPFilterTitles    = (1<<2),
};

typedef NS_ENUM(NSUInteger,MPOVerlayInfoType) {
  MPOverlayInfoPassword,
  MPOverlayInfoUsername,
  MPOverlayInfoURL,
};

NSString *const MPEntryTableUserNameColumnIdentifier = @"MPUserNameColumnIdentifier";
NSString *const MPEntryTableTitleColumnIdentifier = @"MPTitleColumnIdentifier";
NSString *const MPEntryTablePasswordColumnIdentifier = @"MPPasswordColumnIdentifier";
NSString *const MPEntryTableParentColumnIdentifier = @"MPParentColumnIdentifier";
NSString *const MPEntryTableURLColumnIdentifier = @"MPEntryTableURLColumnIdentifier";

NSString *const _MPTableImageCellView = @"ImageCell";
NSString *const _MPTableStringCellView = @"StringCell";
NSString *const _MPTAbleSecurCellView = @"PasswordCell";

NSString *const _toggleFilterURLButton = @"SearchURL";
NSString *const _toggleFilterTitleButton = @"SearchTitle";
NSString *const _toggleFilterUsernameButton = @"SearchUsername";

@interface MPEntryViewController ()

@property (strong) NSArrayController *entryArrayController;
@property (strong) NSArray *filteredEntries;
@property (strong) IBOutlet NSView *filterBar;
@property (weak) IBOutlet NSTableView *entryTable;
@property (strong) IBOutlet NSLayoutConstraint *tableToTop;
@property (weak) IBOutlet NSButton *filterDoneButton;

@property (weak) IBOutlet NSButton *filterTitleButton;
@property (weak) IBOutlet NSButton *filterUsernameButton;
@property (weak) IBOutlet NSButton *filterURLButton;
@property (weak) IBOutlet NSTextField *filterLabelTextField;
@property (weak) IBOutlet NSSearchField *filterSearchField;
@property (weak) IBOutlet HNHGradientView *bottomBar;
@property (weak) IBOutlet NSButton *addEntryButton;

@property (weak) KdbEntry *selectedEntry;

@property (nonatomic, strong) MPEntryTableDataSource *dataSource;

@property (assign, nonatomic) MPFilterModeType filterMode;
@property (strong, nonatomic) NSDictionary *filterButtonToMode;

@end

@implementation MPEntryViewController


- (id)init {
  return [[MPEntryViewController alloc] initWithNibName:@"EntryView" bundle:nil];
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
  self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
  if(self) {
    _filterMode = MPFilterTitles;
    _filterButtonToMode = @{ _toggleFilterUsernameButton : @(MPFilterUsernames),
                           _toggleFilterTitleButton : @(MPFilterTitles),
                           _toggleFilterURLButton : @(MPFilterUrls)
                           };
    _entryArrayController = [[NSArrayController alloc] init];
    _dataSource = [[MPEntryTableDataSource alloc] init];
    _dataSource.viewController = self;
    _selectedEntry = nil;
  }
  return self;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  
}

- (void)didLoadView {
  [self.view setWantsLayer:YES];
  [self _hideFilterBarAnimated:NO];
  
  [_bottomBar setBorderType:HNHBorderTop];
  [self.addEntryButton setAction:[MPActionHelper actionOfType:MPActionAddEntry]];
  
  [self.entryTable setDelegate:self];
  [self.entryTable setDoubleAction:@selector(_columnDoubleClick:)];
  [self.entryTable setTarget:self];
  [self.entryTable setFloatsGroupRows:NO];
  [self.entryTable registerForDraggedTypes:@[MPPasteBoardType]];
  [self _setupEntryMenu];
  
  NSTableColumn *parentColumn = [self.entryTable tableColumns][0];
  NSTableColumn *titleColumn = [self.entryTable tableColumns][1];
  NSTableColumn *userNameColumn = [self.entryTable tableColumns][2];
  NSTableColumn *passwordColumn = [self.entryTable tableColumns][3];
  NSTableColumn *urlColumn = [self.entryTable tableColumns][4];
  
  
  [parentColumn setIdentifier:MPEntryTableParentColumnIdentifier];
  [titleColumn setIdentifier:MPEntryTableTitleColumnIdentifier];
  [userNameColumn setIdentifier:MPEntryTableUserNameColumnIdentifier];
  [passwordColumn setIdentifier:MPEntryTablePasswordColumnIdentifier];
  [urlColumn setIdentifier:MPEntryTableURLColumnIdentifier];
  
	NSSortDescriptor *titleColumSortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"title" ascending:YES selector:@selector(compare:)];
  NSSortDescriptor *userNameSortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"username" ascending:YES selector:@selector(compare:)];
  NSSortDescriptor *urlSortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"url" ascending:YES selector:@selector(compare:)];
  
  [titleColumn setSortDescriptorPrototype:titleColumSortDescriptor];
  [userNameColumn setSortDescriptorPrototype:userNameSortDescriptor];
  [urlColumn setSortDescriptorPrototype:urlSortDescriptor];
  
  [[parentColumn headerCell] setStringValue:@"Group"];
  [[titleColumn headerCell] setStringValue:@"Title"];
  [[userNameColumn headerCell] setStringValue:@"Username"];
  [[passwordColumn headerCell] setStringValue:@"Password"];
  [[urlColumn headerCell] setStringValue:@"URL"];
  
  [self.entryTable bind:NSContentBinding toObject:self.entryArrayController withKeyPath:@"arrangedObjects" options:nil];
  [self.entryTable bind:NSSortDescriptorsBinding toObject:self.entryArrayController withKeyPath:@"sortDescriptors" options:nil];
  [self.entryTable setDataSource:_dataSource];
  
  [parentColumn setHidden:YES];
  
}

- (void)setupNotifications:(MPDocumentWindowController *)windowController {
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(_didChangeCurrentItem:)
                                               name:MPCurrentItemChangedNotification
                                             object:windowController];  
}

#pragma mark NSTableViewDelgate

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
  KdbEntry *entry = [self.entryArrayController arrangedObjects][row];
  
  const BOOL isTitleColumn = [[tableColumn identifier] isEqualToString:MPEntryTableTitleColumnIdentifier];
  const BOOL isGroupColumn = [[tableColumn identifier] isEqualToString:MPEntryTableParentColumnIdentifier];
  const BOOL isPasswordColum = [[tableColumn identifier] isEqualToString:MPEntryTablePasswordColumnIdentifier];
  const BOOL isUsernameColumn = [[tableColumn identifier] isEqualToString:MPEntryTableUserNameColumnIdentifier];
  const BOOL isURLColumn = [[tableColumn identifier] isEqualToString:MPEntryTableURLColumnIdentifier];
  
  NSTableCellView *view = nil;
  if(isTitleColumn || isGroupColumn) {
    view = [tableView makeViewWithIdentifier:_MPTableImageCellView owner:self];
    if( isTitleColumn ) {
      [[view textField] bind:NSValueBinding toObject:entry withKeyPath:MPEntryTitleUndoableKey options:nil];
      [[view imageView] setImage:[MPIconHelper icon:(MPIconType)entry.image]];
    }
    else {
      assert(entry.parent);
      [[view textField] bind:NSValueBinding toObject:entry.parent withKeyPath:MPGroupNameUndoableKey options:nil];
      [[view imageView] setImage:[MPIconHelper icon:(MPIconType)entry.parent.image]];
    }
  }
  else if( isPasswordColum ) {
    view = [tableView makeViewWithIdentifier:_MPTAbleSecurCellView owner:self];
    NSDictionary *options = @{ NSValueTransformerBindingOption : [NSValueTransformer valueTransformerForName:MPStringLengthValueTransformerName] };
    [[view textField] bind:NSValueBinding toObject:entry withKeyPath:MPEntryPasswordUndoableKey options:options];
  }
  else if( isUsernameColumn || isURLColumn ) {
    view = [tableView makeViewWithIdentifier:_MPTableStringCellView owner:self];
    if(isURLColumn) {
      [[view textField] bind:NSValueBinding toObject:entry withKeyPath:MPEntryUrlUndoableKey options:nil];
      //[[view textField] setStringValue:entry.url];
    }
    else {
      [[view textField] bind:NSValueBinding toObject:entry withKeyPath:MPEntryUsernameUndoableKey options:nil];
      //[[view textField] setStringValue:entry.username];
    }
  }
  
  return view;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
  if([self.entryTable selectedRow] < 0 || [[_entryTable selectedRowIndexes] count] > 1) {
    self.selectedEntry = nil;
  }
  else {
    self.selectedEntry = [self.entryArrayController arrangedObjects][[self.entryTable selectedRow]];
  }
  [[NSNotificationCenter defaultCenter] postNotificationName:MPDidChangeSelectedEntryNotification object:self userInfo:nil];
}

#pragma mark Notifications
- (void)_didChangeCurrentItem:(NSNotification *)notification {
  if([self _showsFilterBar]) {
    //[self.filterSearchField setStringValue:@""];
    [self clearFilter:nil];
  }
  MPDocumentWindowController *sender = [notification object];
  id item = sender.currentItem;
  /*
   Filter? If no group is selected, we shouldn display a list of entries
   */
  if(!sender.currentGroup) {
    [self.entryArrayController unbind:NSContentArrayBinding];
    [self.entryArrayController setContent:nil];
    return;
  }
  /*
   If a grup is the current item, see if we already show that group
   */
  if(item == sender.currentGroup) {
    if([[self.entryArrayController content] count] > 0) {
      KdbEntry *entry = [[self.entryArrayController content] lastObject];
      if(entry.parent == item) {
        return; // we are showing the correct object right now.
      }
    }
    [self.entryArrayController bind:NSContentArrayBinding toObject:item withKeyPath:@"entries" options:nil];
  }
}


#pragma mark Filtering

- (void)showFilter:(id)sender {
  [self _showFilterBarAnimated:NO];
}

- (BOOL)hasFilter {
  return ([self.filter length] > 0);
}

- (void)setFilter:(NSString *)filter {
  if(_filter != filter) {
    _filter = filter;
    [self updateFilter];
  }
}

- (void)clearFilter:(id)sender {
  self.filter = nil;
  [[self.entryTable tableColumnWithIdentifier:MPEntryTableParentColumnIdentifier] setHidden:YES];
  [self _hideFilterBarAnimated:YES];
}

- (void)updateFilter {
  [self _showFilterBarAnimated:YES];
  if(![self hasFilter]) {
    return;
  }
  
  dispatch_queue_t backgroundQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
  dispatch_async(backgroundQueue, ^{
    
    NSMutableArray *prediactes = [NSMutableArray arrayWithCapacity:3];
    if( [self _shouldFilterTitles] ) {
      [prediactes addObject:[NSPredicate predicateWithFormat:@"SELF.title CONTAINS[cd] %@", self.filter]];
    }
    if( [self _shouldFilterUsernames] ) {
      [prediactes addObject:[NSPredicate predicateWithFormat:@"SELF.username CONTAINS[cd] %@", self.filter]];
    }
    if( [self _shouldFilterURLs] ) {
      [prediactes addObject:[NSPredicate predicateWithFormat:@"SELF.url CONTAINS[cd] %@", self.filter]];
    }
    NSPredicate *fullFilter = [NSCompoundPredicate orPredicateWithSubpredicates:prediactes];
    MPDocument *document = [[self windowController] document];
    self.filteredEntries = [[document.root childEntries] filteredArrayUsingPredicate:fullFilter];
    
    dispatch_sync(dispatch_get_main_queue(), ^{
      [self.entryArrayController unbind:NSContentArrayBinding];
      [self.entryArrayController setContent:self.filteredEntries];
      [[self.entryTable tableColumnWithIdentifier:MPEntryTableParentColumnIdentifier] setHidden:NO];
    });
  });
  
}

- (void)updateFilterText:(id)sender {
  self.filter = [self.filterSearchField stringValue];
}

- (void)setupFilterBar {
  if(!self.filterBar) {
    [[NSBundle mainBundle] loadNibNamed:@"FilterBar" owner:self topLevelObjects:nil];
    [self.filterURLButton setIdentifier:_toggleFilterURLButton];
    [self.filterUsernameButton setIdentifier:_toggleFilterUsernameButton];
    [self.filterTitleButton setIdentifier:_toggleFilterTitleButton];
    [[self.filterLabelTextField cell] setBackgroundStyle:NSBackgroundStyleRaised];
    [self.filterDoneButton setAction:@selector(clearFilter:)];
    [self.filterDoneButton setTarget:nil];
    
    [self.filterSearchField setAction:@selector(updateFilterText:)];
    [[self.filterSearchField cell] setSendsSearchStringImmediately:NO];
  }
}

- (BOOL)_showsFilterBar {
  return ( nil != [self.filterBar superview]);
}

#pragma mark UI Feedback

- (void)_showFilterBarAnimated:(BOOL)animate {
  
  animate = NO;
  
  if(!self.filterBar) {
    [self setupFilterBar];
  }
  /*
   Make sure the buttons are set correctyl every time
   */
  [self.filterTitleButton setState:[self _shouldFilterTitles] ? NSOnState : NSOffState];
  [self.filterURLButton setState:[self _shouldFilterURLs] ? NSOnState : NSOffState ];
  [self.filterUsernameButton setState:[self _shouldFilterUsernames] ? NSOnState : NSOffState];
  
  if([self _showsFilterBar]) {
    return; // nothing to to
  }
  
  NSView *scrollView = [_entryTable enclosingScrollView];
  NSDictionary *views = NSDictionaryOfVariableBindings(scrollView, _filterBar);
  [self.view layout];
  [self.view removeConstraint:self.tableToTop];
  [self.view addSubview:self.filterBar];
  [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[_filterBar]|" options:0 metrics:nil views:views]];
  [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[_filterBar(==30)]-0-[scrollView]" options:0 metrics:nil views:views]];
  
  
  if(animate) {
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
      context.duration = STATUS_BAR_ANIMATION_TIME;
      context.allowsImplicitAnimation = YES;
      [self.view layoutSubtreeIfNeeded];
    } completionHandler:nil] ;
  }
  else {
    [self.view layoutSubtreeIfNeeded];
  }
}

- (void)_hideFilterBarAnimated:(BOOL)animate {
  
  animate = NO;
  
  if(![self _showsFilterBar]) {
    return; // nothing to do;
  }
  
  [self.filterBar removeFromSuperview];
  [self.view addConstraint:self.tableToTop];
  
  if(animate) {
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
      context.duration = STATUS_BAR_ANIMATION_TIME;
      context.allowsImplicitAnimation = YES;
      [self.view layoutSubtreeIfNeeded];
    } completionHandler:nil] ;
  }
  else {
    [self.view layoutSubtreeIfNeeded];
  }
}

- (void)_copyToPasteboard:(NSString *)data overlayInfo:(MPOVerlayInfoType)overlayInfoType {
  if(data) {
    [[MPPasteBoardController defaultController] copyObjects:@[ data ]];
  }
  NSImage *infoImage = nil;
  NSString *infoText = nil;
  switch (overlayInfoType) {
    case MPOverlayInfoPassword:
      infoImage = [[NSBundle mainBundle] imageForResource:@"00_PasswordTemplate"];
      infoText = NSLocalizedString(@"COPIED_PASSWORD", @"Password was copied to the pasteboard");
      break;
      
    case MPOverlayInfoURL:
      infoImage = [[NSBundle mainBundle] imageForResource:@"01_PackageNetworkTemplate"];
      infoText = NSLocalizedString(@"COPIED_URL", @"URL was copied to the pasteboard");
      break;
      
    case MPOverlayInfoUsername:
      infoImage = [[NSBundle mainBundle] imageForResource:@"09_IdentityTemplate"];
      infoText = NSLocalizedString(@"COPIED_USERNAME", @"Username was copied to the pasteboard");
      break;
  }
  [[MPOverlayWindowController sharedController] displayOverlayImage:infoImage label:infoText atView:self.view];
}

#pragma mark EntryMenu

- (void)_setupEntryMenu {
  
  NSMenu *menu = [[NSMenu alloc] init];
  NSArray *items = [MPContextMenuHelper contextMenuItemsWithItems:MPContextMenuFull];
  for(NSMenuItem *item in items) {
    [menu addItem:item];
  }
  [self.entryTable setMenu:menu];
}

#pragma makr Action Helper

- (KdbEntry *)_clickedOrSelectedEntry {
  NSInteger activeRow = [self.entryTable clickedRow];
  /* Fallback to selection e.g. for toolbar actions */
  if(activeRow < 0 ) {
    activeRow = [self.entryTable selectedRow];
  }
  if(activeRow >= 0 && activeRow <= [[self.entryArrayController arrangedObjects] count]) {
    return [self.entryArrayController arrangedObjects][activeRow];
  }
  return nil;
}

#pragma mark Actions

- (void)copyPassword:(id)sender {
  KdbEntry *selectedEntry = [self _clickedOrSelectedEntry];
  if(selectedEntry) {
    [self _copyToPasteboard:selectedEntry.password overlayInfo:MPOverlayInfoPassword];
  }
}

- (void)copyUsername:(id)sender {
  KdbEntry *selectedEntry = [self _clickedOrSelectedEntry];
  if(selectedEntry) {
    [self _copyToPasteboard:selectedEntry.username overlayInfo:MPOverlayInfoUsername];
  }
}

- (void)copyURL:(id)sender {
  KdbEntry *selectedEntry = [self _clickedOrSelectedEntry];
  if(selectedEntry) {
    [self _copyToPasteboard:selectedEntry.url overlayInfo:MPOverlayInfoURL];
  }
}

- (void)openURL:(id)sender {
  KdbEntry *selectedEntry = [self _clickedOrSelectedEntry];
  if(selectedEntry && [selectedEntry.url length] > 0) {
    NSURL *webURL = [NSURL URLWithString:selectedEntry.url];
    [[NSWorkspace sharedWorkspace] openURL:webURL];
  }
}

- (void)deleteNode:(id)sender {
  KdbEntry *entry =[self _clickedOrSelectedEntry];
  MPDocument *document = [[self windowController] document];
  [document group:entry.parent removeEntry:entry];
}

- (void)_toggleFilterSpace:(id)sender {
  NSButton *button = sender;
  NSNumber *value = self.filterButtonToMode[[button identifier]];
  MPFilterModeType toggledMode = (MPFilterModeType)[value intValue];
  switch ([button state]) {
    case NSOnState:
      self.filterMode |= toggledMode;
      break;
      
    case NSOffState:
      self.filterMode ^= toggledMode;
      break;
      
    default:
      break;
  }
}

- (void)_columnDoubleClick:(id)sender {
  if(0 == [[self.entryArrayController arrangedObjects] count]) {
    return; // No data available
  }
  NSTableColumn *column = [self.entryTable tableColumns][[self.entryTable clickedColumn]];
  NSString *identifier = [column identifier];
  if([identifier isEqualToString:MPEntryTablePasswordColumnIdentifier]) {
    [self copyPassword:nil];
  }
  else if([identifier isEqualToString:MPEntryTableUserNameColumnIdentifier]) {
    [self copyUsername:nil];
  }
  else if([identifier isEqualToString:MPEntryTableURLColumnIdentifier]) {
    [self copyURL:nil];
  }
}

- (void)setFilterMode:(MPFilterModeType)newFilterMode {
  if(_filterMode != newFilterMode) {
    if(newFilterMode == MPFilterNone) {
      newFilterMode = MPFilterTitles;
    }
    _filterMode = newFilterMode;
    [self updateFilter];
  }
}

- (BOOL)_shouldFilterTitles {
  return ( MPFilterNone != (self.filterMode & MPFilterTitles));
}

- (BOOL)_shouldFilterURLs {
  return ( MPFilterNone != (self.filterMode & MPFilterUrls));
}

- (BOOL)_shouldFilterUsernames {
  return ( MPFilterNone != (self.filterMode & MPFilterUsernames));
}

@end
