//
//  ViewController.m
//  EbbyCalc
//
//  Created by Ansel Rognlie on 10/23/19.
//  Copyright © 2019 Ansel Rognlie. All rights reserved.
//

//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.

#import <AVFoundation/AVFoundation.h>

#import "ViewController.h"

#import "EWCAudio.h"
#import "EWCGridLayoutView.h"
#import "EWCRoundedCornerButton.h"
#import "EWCCalculator.h"
#import "EWCCalculatorUserDefaultsData.h"
#import "EWCLabelEditManager.h"
#import "EWCCopyableLabel.h"
#import "EWCKeyCommandCalculatorRecord.h"

/**
  `EWCApplicationLayout` represents the orientation of the application layout.
*/
typedef NS_ENUM(NSInteger, EWCApplicationLayout) {
  EWCApplicationDefaultLayout = 0,
  EWCApplicationWideLayout = 1,
  EWCApplicationTallLayout,
};

/**
  `EWCLayoutConstants` groups several values used for UI layout that can change according to the layout
 */
typedef struct {
  /**
    Used to calculate the text button font size using the current minimum dimension.
   */
  const float textSizeAsPercentOfHeight;

  /**
    Used to calculate the status indicator font size using the current minimum dimension.
   */
  const float statusSizeAsPercentOfHeight;

  /**
    Used to calculate the digit button font size using the current minimum dimension.
   */
  const float digitSizeAsPercentOfHeight;

  /**
    Used to calculate the text button font size using the current minimum dimension.
   */
  const float operatorSizeAsPercentOfHeight;

  /**
    Used to calculate the display font size using the current minimum dimension.
   */
  const float displaySizeAsPercentOfHeight;

  /**
    Used to calculate the display height from the font size it will need to display.
   */
  const float displayHeightFromFontSize;

  /**
    The minimum spacing between button rows as a percentage of height.
   */
  const float minimumRowGutter;

  /**
    The minimum spacing between button columns as a percentage of width.
   */
  const float minimumColumnGutter;
} EWCLayoutConstants;

@interface ViewController () {
  IBOutlet EWCGridLayoutView *_grid;  // the control the performs the grid layout logic
  IBOutlet EWCCopyableLabel *_displayArea;  // the control presenting the calculator display, enabled for copy and paste
  IBOutlet NSLayoutConstraint *_gridTopConstraint;  // the constraint used to set the top of the grid
  IBOutlet NSLayoutConstraint *_gridBottomConstraint;  // used to read the constraint constant of the bottom of the grid
  EWCApplicationLayout _layout;  // tracks the layout orientation
  CGFloat _layoutWidth;  // stores the last width
  CGFloat _layoutHeight;  // stores the last height
  IBOutlet UILabel *_memoryIndicator;  // used to control the visibility and font size of the memory indicator
  IBOutlet UILabel *_errorIndicator;  // used to control the visibility and font size of the error indicator
  IBOutlet UILabel *_taxIndicator;  // used to control the visibility and font size of the tax indicator
  IBOutlet UILabel *_taxPlusIndicator;  // used to control the visibility and font size of the tax included indicator
  IBOutlet UILabel *_taxMinusIndicator;  // used to control the visibility and font size of the tax deducted indicator
  IBOutlet UILabel *_taxPercentIndicator;  // used to control the visibility and font size of the tax percent indicator
  IBOutlet NSLayoutConstraint *_statusLeftConstraint;  // used to adjust the constraint constant at run time
  IBOutlet NSLayoutConstraint *_statusRightConstraint;  // used to adjust the constraint constant at run time
  NSArray<UILabel *> *_statusLabels;  // iterable collection of all the status labels
  NSMutableArray<EWCRoundedCornerButton *> *_textButtons;  // iterable collection of all the "text" (e.g. mrc) buttons and sub operator (e.g. %) buttons, since they have the same font size
  NSMutableArray<EWCRoundedCornerButton *> *_digitButtons;  // iterable collection of all the digit buttons
  NSMutableArray<EWCRoundedCornerButton *> *_opButtons;  // iterable collection of all the main operator (e.g. +) buttons
  NSMutableArray<EWCRoundedCornerButton *> *_allButtons;  // iterable collection of all buttons
  EWCCalculator *_calculator;  // our calculator model
  UIButton *_memoryButton;  // reference to the memory button so the (accessibility) label can be updated
  UIButton *_clearButton;  // reference to the clear button so the labels can be updated
  UIButton *_rateButton;  // reference to the rate button so the (accessibility) label can be updated
  UIButton *_taxPlusButton;  // reference to the tax+ button so the labels can be updated
  UIButton *_taxMinusButton;  // reference to the tax- button so the labels can be updated
  EWCLabelEditManager *_labelManager;  // provides the logic for attaching the edit menu to a copy/paste-enabled label
  EWCLayoutConstants const *_currentLayout;  // points to the currently configured layout constants

  NSMutableArray<AVAudioPlayer *> *_players;  // tracks sounds that have been started
  BOOL _playKeyClicks;  // preference setting whether to use audible key clicks
  NSData *_clickData;  // sound data for regular clicks
  NSData *_deleteData;  // sound data for the clear key click
  NSData *_modifyData;  // sound data for the rate shift key click

  NSArray<EWCKeyCommandCalculatorRecord *> *_keyMappings;  // the single authoratative mapping from a hardware key to a calculator key
  NSArray<UIKeyCommand *> *_keyCommands;  // the hardware key commands we are interested in
  NSDictionary<NSString *, NSNumber *> *_commandToKey;  // mapping of keyboard commands to calculator keys
}

///------------------------------------------------------
/// @name Internal Status Indicator Property Declarations
///------------------------------------------------------

@property (nonatomic, getter=isMemoryVisible) BOOL memoryVisible;
@property (nonatomic, getter=isErrorVisible) BOOL errorVisible;
@property (nonatomic, getter=isTaxVisible) BOOL taxVisible;
@property (nonatomic, getter=isTaxPlusVisible) BOOL taxPlusVisible;
@property (nonatomic, getter=isTaxMinusVisible) BOOL taxMinusVisible;
@property (nonatomic, getter=isTaxPercentVisible) BOOL taxPercentVisible;

@end

///----------------------
/// @name Sound Constants
///----------------------

static char const * const s_keyClickName = "key_press_click";
static char const * const s_keyDeleteName = "key_press_delete";
static char const * const s_keyModifyName = "key_press_modifier";
static char const * const s_soundExt = ".wav";
static const float s_soundVolume = 0.8;

///-------------------------
/// @name Settings Constants
///-------------------------

static char const * const s_playClicksPref = "play_key_clicks_preference";

///------------------------
/// @name Mapping Constants
///------------------------

static char const * const s_escapeMarker = "ESCAPE";

///-----------------------
/// @name Layout Constants
///-----------------------

static const float s_tallGridHeightWidthRatio = 1.700;  // the aspect ratio that determines whether to layout the buttons in tall or wide mode

static const float s_minimumDisplayScaleFactor = 0.25;  // the minimum scale font that can be applied to the display to fit the contents on screen
static const int s_maximumDigits = 16;  // the number of digits we will support

static const float s_narrowLayoutBase = 0.037;  // base layout value for narrow layout
static const float s_wideLayoutBase = 0.045;  // base layout value for wide layout
static const float s_tallLayoutBase = 0.030;  // base layout value for tall layout

/**
  Layout constants for the narrow layout (wide layout, but width is smaller than height).
 */
static const EWCLayoutConstants s_narrowLayoutConstants = {
  s_narrowLayoutBase,  // textSizeAsPercentOfHeight
  s_narrowLayoutBase * 0.5,  // statusSizeAsPercentOfHeight
  s_narrowLayoutBase * 2,  // digitSizeAsPercentOfHeight
  s_narrowLayoutBase * 2,  // operatorSizeAsPercentOfHeight
  s_narrowLayoutBase * 3.7,  // displaySizeAsPercentOfHeight
  1.500,  // displayHeightFromFontSize
  0.020,  // minimumRowGutter
  0.020,  // minimumColumnGutter
};

/**
 Layout constants for the wide layout (wide layout, and width is larger than height).
*/
static const EWCLayoutConstants s_wideLayoutConstants = {
  s_wideLayoutBase,  // textSizeAsPercentOfHeight
  s_wideLayoutBase * 0.5,  // statusSizeAsPercentOfHeight
  s_wideLayoutBase * 2,  // digitSizeAsPercentOfHeight
  s_wideLayoutBase * 2,  // operatorSizeAsPercentOfHeight
  s_wideLayoutBase * 2.6,  // displaySizeAsPercentOfHeight
  1.500,  // displayHeightFromFontSize
  0.030,  // minimumRowGutter
  0.010,  // minimumColumnGutter
};

/**
 Layout constants for the tall layout (greater than tall aspect ratio).
*/
static const EWCLayoutConstants s_tallLayoutConstants = {
  s_tallLayoutBase,  // textSizeAsPercentOfHeight
  s_tallLayoutBase * 0.5,  // statusSizeAsPercentOfHeight
  s_tallLayoutBase * 1.8,  // digitSizeAsPercentOfHeight
  s_tallLayoutBase * 1.7,  // operatorSizeAsPercentOfHeight
  s_tallLayoutBase * 2.8,  // displaySizeAsPercentOfHeight
  1.500,  // displayHeightFromFontSize
  0.020,  // minimumRowGutter
  0.030,  // minimumColumnGutter
};


@implementation ViewController

///---------------------------------------------------------
/// @name Internal Status Indicator Property Implementations
///---------------------------------------------------------

/**
  Returns the display state of the memory status indicator
 */
- (BOOL)isMemoryVisible {
  return ! _memoryIndicator.hidden;
}

/**
 Sets the display state of the memory status indicator
*/
- (void)setMemoryVisible:(BOOL)value {
  _memoryIndicator.hidden = ! value;
}

/**
 Returns the display state of the error status indicator
*/
- (BOOL)isErrorVisible {
  return ! _errorIndicator.hidden;
}

/**
 Sets the display state of the error status indicator
*/
- (void)setErrorVisible:(BOOL)value {
  _errorIndicator.hidden = ! value;
}

/**
 Returns the display state of the tax status indicator
*/
- (BOOL)isTaxVisible {
  return ! _taxIndicator.hidden;
}

/**
 Sets the display state of the tax status indicator
*/
- (void)setTaxVisible:(BOOL)value {
  _taxIndicator.hidden = ! value;
}

/**
 Returns the display state of the tax added status indicator
*/
- (BOOL)isTaxPlusVisible {
  return ! _taxPlusIndicator.hidden;
}

/**
 Sets the display state of the tax added status indicator
*/
- (void)setTaxPlusVisible:(BOOL)value {
  _taxPlusIndicator.hidden = ! value;
}

/**
 Returns the display state of the tax deducted status indicator
*/
- (BOOL)isTaxMinusVisible {
  return ! _taxMinusIndicator.hidden;
}

/**
 Sets the display state of the tax deducted status indicator
*/
- (void)setTaxMinusVisible:(BOOL)value {
  _taxMinusIndicator.hidden = ! value;
}

/**
 Returns the display state of the tax percent status indicator
*/
- (BOOL)isTaxPercentVisible {
  return ! _taxPercentIndicator.hidden;
}

/**
 Sets the display state of the tax percent status indicator
*/
- (void)setTaxPercentVisible:(BOOL)value {
  _taxPercentIndicator.hidden = ! value;
}

///---------------------------------
/// @name UIViewController Overrides
///---------------------------------

/**
  Informs iOS to use light content in the status bar, since our app is dark.
 */
- (UIStatusBarStyle)preferredStatusBarStyle {
  return UIStatusBarStyleLightContent;
}

/**
  Performs initial view and state configuration.
 */
- (void)viewDidLoad {
  [super viewDidLoad];

  // initialize state that tracks layout to values that will force an initial layout
  _layout = EWCApplicationDefaultLayout;
  _layoutWidth = 0;
  _layoutHeight = 0;
  _currentLayout = &s_wideLayoutConstants;

  _textButtons = [NSMutableArray<EWCRoundedCornerButton *> new];
  _digitButtons = [NSMutableArray<EWCRoundedCornerButton *> new];
  _opButtons = [NSMutableArray<EWCRoundedCornerButton *> new];
  _allButtons = [NSMutableArray<EWCRoundedCornerButton *> new];

  _displayArea.adjustsFontSizeToFitWidth = YES;
  _displayArea.minimumScaleFactor = s_minimumDisplayScaleFactor;

  [self setupCalculator];
  [self allocateButtons];

  // trun off all status indicators
  self.memoryVisible = NO;
  self.errorVisible = NO;
  self.taxVisible = NO;
  self.taxPlusVisible = NO;
  self.taxMinusVisible = NO;
  self.taxPercentVisible = NO;

  // collect status indicators into a collection for later font changes
  _statusLabels = @[
    _memoryIndicator,
    _errorIndicator,
    _taxIndicator,
    _taxPlusIndicator,
    _taxMinusIndicator,
    _taxPercentIndicator,
  ];

  // setup the copy paste managements on the display
  _labelManager = [EWCLabelEditManager new];
  _displayArea.editDelegate = self;
  _labelManager.managedLabel = _displayArea;
  ViewController __weak *weakSelf = self;
  _labelManager.swipeHandler = ^(UILabel *label, UISwipeGestureRecognizerDirection direction) {
    [weakSelf onBackspacePressed];
  };

  // layout everything
  [self updateLayoutOnChange];

  // perform initial display updated from calculator state
  [self updateDisplayFromCalculator];

  // load the sound data we need for key input
  [self loadSoundData];

  // initialize the hardware keys we care about
  [self setupKeyCommands];

  // if just installed, we need to register our defaults
  [self registerDefaultPreferencesIfNeeded];
}

/**
  Lays out the update once the system is about to perform subview layout.

  At this point, the control dimensions are set and can be used to size the children.
 */
- (void)viewWillLayoutSubviews {
  [self updateLayoutOnChange];
}

/**
  Mark that this controller can receive input events directly.

  This allows the OS to give us key commands that we care about.
 */
- (BOOL)canBecomeFirstResponder
{
    return YES;
}

/**
  Tell the OS the keys we care about.
 */
- (NSArray *)keyCommands {
  return _keyCommands;
}

///-------------------------
/// @name View Setup Methods
///-------------------------

/**
  Configure the calculator, including the notification callback.
 */
- (void)setupCalculator {
  _calculator = [EWCCalculator new];

  __weak ViewController *controller = self;
  [_calculator registerUpdateCallbackWithBlock:^{
    [controller updateDisplayFromCalculator];
  }];

  _calculator.maximumDigits = s_maximumDigits;
  _calculator.dataProvider = [EWCCalculatorUserDefaultsData new];

  // make sure that we announce the initial displayed valued
  [self dispatchAnnouncement:_displayArea];
}

/**
  Creates all the calculator buttons, adding them to various lists for later font size management.

  This method does NOT actually add the buttons to the view.  That occurs during layout.
 */
- (void)allocateButtons {
  EWCRoundedCornerButton *button = nil;

  CGRect screen = self.view.bounds;
  CGFloat sWidth = screen.size.width, sHeight = screen.size.height;
  CGFloat fontDim = (sWidth < sHeight) ? sWidth : sHeight;

  button = [self makeDigitButton:NSLocalizedString(@"Zero Button", @"label for the 0 button")
    accessibilityLabel:NSLocalizedString(@"Zero Aria Label", @"voiceover label for the 0 button")
    tag:EWCCalculatorZeroKey forWidth:fontDim];
  [_digitButtons addObject:button];
  [_allButtons addObject:button];

  button = [self makeDigitButton:NSLocalizedString(@"One Button", @"label for the 1 button")
    accessibilityLabel:NSLocalizedString(@"One Aria Label", @"voiceover label for the 1 button")
    tag:EWCCalculatorOneKey forWidth:fontDim];
  [_digitButtons addObject:button];
  [_allButtons addObject:button];

  button = [self makeDigitButton:NSLocalizedString(@"Two Button", @"label for the 2 button")
    accessibilityLabel:NSLocalizedString(@"Two Aria Label", @"voiceover label for the 2 button")
    tag:EWCCalculatorTwoKey forWidth:fontDim];
  [_digitButtons addObject:button];
  [_allButtons addObject:button];

  button = [self makeDigitButton:NSLocalizedString(@"Three Button", @"label for the 3 button")
    accessibilityLabel:NSLocalizedString(@"Three Aria Label", @"voiceover label for the 3 button")
    tag:EWCCalculatorThreeKey forWidth:fontDim];
  [_digitButtons addObject:button];
  [_allButtons addObject:button];

  button = [self makeDigitButton:NSLocalizedString(@"Four Button", @"label for the 4 button")
    accessibilityLabel:NSLocalizedString(@"Four Aria Label", @"voiceover label for the 4 button")
    tag:EWCCalculatorFourKey forWidth:fontDim];
  [_digitButtons addObject:button];
  [_allButtons addObject:button];

  button = [self makeDigitButton:NSLocalizedString(@"Five Button", @"label for the 5 button")
    accessibilityLabel:NSLocalizedString(@"Five Aria Label", @"voiceover label for the 5 button")
    tag:EWCCalculatorFiveKey forWidth:fontDim];
  [_digitButtons addObject:button];
  [_allButtons addObject:button];

  button = [self makeDigitButton:NSLocalizedString(@"Six Button", @"label for the 6 button")
    accessibilityLabel:NSLocalizedString(@"Six Aria Label", @"voiceover label for the 6 button")
    tag:EWCCalculatorSixKey forWidth:fontDim];
  [_digitButtons addObject:button];
  [_allButtons addObject:button];

  button = [self makeDigitButton:NSLocalizedString(@"Seven Button", @"label for the 7 button")
    accessibilityLabel:NSLocalizedString(@"Seven Aria Label", @"voiceover label for the 7 button")
    tag:EWCCalculatorSevenKey forWidth:fontDim];
  [_digitButtons addObject:button];
  [_allButtons addObject:button];

  button = [self makeDigitButton:NSLocalizedString(@"Eight Button", @"label for the 8 button")
    accessibilityLabel:NSLocalizedString(@"Eight Aria Label", @"voiceover label for the 8 button")
    tag:EWCCalculatorEightKey forWidth:fontDim];
  [_digitButtons addObject:button];
  [_allButtons addObject:button];

  button = [self makeDigitButton:NSLocalizedString(@"Nine Button", @"label for the 9 button")
    accessibilityLabel:NSLocalizedString(@"Nine Aria Label", @"voiceover label for the 9 button")
    tag:EWCCalculatorNineKey forWidth:fontDim];
  [_digitButtons addObject:button];
  [_allButtons addObject:button];

  button = [self makeTextButton:NSLocalizedString(@"Clear Button", "label for the button that clears the input")
    accessibilityLabel:NSLocalizedString(@"Clear Aria Label", @"voiceover label for the button that clears the input")
    tag:EWCCalculatorClearKey forWidth:fontDim];
  [_textButtons addObject:button];
  _clearButton = button;
  [_allButtons addObject:button];

  button = [self makeTextButton:NSLocalizedString(@"Rate Button", "label for the button that switches to tax rate management mode")
    accessibilityLabel:NSLocalizedString(@"Rate Tax Mode Aria Label", @"voiceover label for the button that switches to tax rate management mode")
    tag:EWCCalculatorRateKey forWidth:fontDim];
  [button setTitleColor:[ViewController shiftedTextColor]
    forState:UIControlStateNormal];
  [_textButtons addObject:button];
  _rateButton = button;
  [_allButtons addObject:button];

  button = [self makeTextButton:NSLocalizedString(@"Tax+ Button", "label for the button that adds tax to the current value")
    accessibilityLabel:NSLocalizedString(@"Tax+ Aria Label", @"voiceover label for the button that adds tax to the current value")
    tag:EWCCalculatorTaxPlusKey forWidth:fontDim];
  [_textButtons addObject:button];
  _taxPlusButton = button;
  [_allButtons addObject:button];

  button = [self makeTextButton:NSLocalizedString(@"Tax- Button", "label for the button that removes tax from the current value")
    accessibilityLabel:NSLocalizedString(@"Tax- Aria Label", @"voiceover label for the button that removes tax from the current value")
    tag:EWCCalculatorTaxMinusKey forWidth:fontDim];
  [_textButtons addObject:button];
  _taxMinusButton = button;
  [_allButtons addObject:button];

  button = [self makeTextButton:NSLocalizedString(@"Memory Button", @"label for the button that retrieves and clears the memory")
    accessibilityLabel:NSLocalizedString(@"Memory Aria Label", @"voiceover label for the button that retrieves and clears the memory")
    tag:EWCCalculatorMemoryKey forWidth:fontDim];
  [_textButtons addObject:button];
  _memoryButton = button;
  [_allButtons addObject:button];

  button = [self makeTextButton:NSLocalizedString(@"Memory+ Button", @"label for the button that adds to the memory")
    accessibilityLabel:NSLocalizedString(@"Memory+ Aria Label", @"voiceover label for the button that adds to the memory")
    tag:EWCCalculatorMemoryPlusKey forWidth:fontDim];
  [_textButtons addObject:button];
  [_allButtons addObject:button];

  button = [self makeTextButton:NSLocalizedString(@"Memory- Button", @"label for the button that subtracts from the memory")
    accessibilityLabel:NSLocalizedString(@"Memory- Aria Label", @"voiceover label for the button that subtracts from the memory")
    tag:EWCCalculatorMemoryMinusKey forWidth:fontDim];
  [_textButtons addObject:button];
  [_allButtons addObject:button];

  button = [self makeMainOperatorButton:NSLocalizedString(@"Add Button", @"label for the button that performs addition")
    accessibilityLabel:NSLocalizedString(@"Add Aria Label", @"voiceover label for the button that performs addition")
    tag:EWCCalculatorAddKey forWidth:fontDim];
  [_opButtons addObject:button];
  [_allButtons addObject:button];

  button = [self makeMainOperatorButton:NSLocalizedString(@"Subtract Button", @"label for the button that performs subtraction")
    accessibilityLabel:NSLocalizedString(@"Subtract Aria Label", @"voiceover label for the button that performs subtraction")
    tag:EWCCalculatorSubtractKey forWidth:fontDim];
  [_opButtons addObject:button];
  [_allButtons addObject:button];

  button = [self makeMainOperatorButton:NSLocalizedString(@"Multiply Button", @"label for the button that performs multiplication")
    accessibilityLabel:NSLocalizedString(@"Multiply Aria Label", @"voiceover label for the button that performs multiplication")
    tag:EWCCalculatorMultiplyKey forWidth:fontDim];
  [_opButtons addObject:button];
  [_allButtons addObject:button];

  button = [self makeMainOperatorButton:NSLocalizedString(@"Divide Button", @"label for the button that performs division")
    accessibilityLabel:NSLocalizedString(@"Divide Aria Label", @"voiceover label for the button that performs division")
    tag:EWCCalculatorDivideKey forWidth:fontDim];
  [_opButtons addObject:button];
  [_allButtons addObject:button];

  button = [self makeSubOperatorButton:NSLocalizedString(@"Sign Button", @"label for the button that toggles the sign")
    accessibilityLabel:NSLocalizedString(@"Sign Aria Label", @"voiceover label for the button that toggles the sign")
    tag:EWCCalculatorSignKey forWidth:fontDim];
  [_textButtons addObject:button];
  [_allButtons addObject:button];

  button = [self makeDigitButton:NSLocalizedString(@"Decimal Button", @"label for the button that designates the decimal point")
    accessibilityLabel:NSLocalizedString(@"Decimal Aria Label", @"voiceover label for the button that designates the decimal point")
    tag:EWCCalculatorDecimalKey forWidth:fontDim];
  [_digitButtons addObject:button];
  [_allButtons addObject:button];

  button = [self makeSubOperatorButton:NSLocalizedString(@"Percent Button", @"label for the button that take percents")
    accessibilityLabel:NSLocalizedString(@"Percent Aria Label", @"voiceover label for the button that take percents")
    tag:EWCCalculatorPercentKey forWidth:fontDim];
  [_textButtons addObject:button];
  [_allButtons addObject:button];

  button = [self makeSubOperatorButton:NSLocalizedString(@"Sqrt Button", @"label for the button that performs square roots")
    accessibilityLabel:NSLocalizedString(@"Sqrt Aria Label", @"voiceover label for the button that performs square roots")
    tag:EWCCalculatorSqrtKey forWidth:fontDim];
  [_textButtons addObject:button];
  [_allButtons addObject:button];

  button = [self makeDigitButton:NSLocalizedString(@"Equal Button", @"label for the button that executes operations")
    accessibilityLabel:NSLocalizedString(@"Equal Aria Label", @"voiceover label for the button that executes operations")
    tag:EWCCalculatorEqualKey forWidth:fontDim];
  [_digitButtons addObject:button];
  [_allButtons addObject:button];
}

/**
  Preload the data for the sounds.
 */
- (void)loadSoundData {
  char const * const names[] = {
    s_keyClickName,
    s_keyDeleteName,
    s_keyModifyName};
  const int soundCount = sizeof(names) / sizeof(char *);

  NSData * __strong *data[] = {
    &_clickData,
    &_deleteData,
    &_modifyData,
  };

  for (int i = 0; i < soundCount; ++i) {
    NSString *path = [[NSBundle mainBundle] pathForResource:@(names[i]) ofType:@(s_soundExt)];
    *(data[i]) = [NSData dataWithContentsOfFile:path];
  }

  _players = [NSMutableArray array];
}

///------------------------------
/// @name Key Input Event Handler
///------------------------------

/**
  Helper method to get a localized key mapping.

  @param mapping The base name of the key mapping to lookup.

  @return The string to register with the UIKeyCommand shortcut for the calculator key.
 */
- (NSString *)getLocalizedKeyMapping:(NSString *)mapping {

  NSString *lookup = [NSString stringWithFormat:@"%@ Key Mapping", mapping];
  NSString *str = NSLocalizedString(lookup, @"");

  // Fix up special mappings
  if ([str isEqualToString:@(s_escapeMarker)]) {
    str = UIKeyInputEscape;
  }

  return str;
}

/**
  Setup the collection of key commands we will respond to.
 */
- (void)setupKeyCommands {
  _keyMappings = @[
    [self makeKeyCommandRecordForInput:[self getLocalizedKeyMapping:@"Enter"] calculatorKey:EWCCalculatorEqualKey],
    [self makeKeyCommandRecordForInput:[self getLocalizedKeyMapping:@"Backspace"] calculatorKey:EWCCalculatorBackspaceKey],
    // digits
    [self makeKeyCommandRecordForInput:[self getLocalizedKeyMapping:@"Decimal"] calculatorKey:EWCCalculatorDecimalKey],
    [self makeKeyCommandRecordForInput:[self getLocalizedKeyMapping:@"Zero"] calculatorKey:EWCCalculatorZeroKey],
    [self makeKeyCommandRecordForInput:[self getLocalizedKeyMapping:@"One"] calculatorKey:EWCCalculatorOneKey],
    [self makeKeyCommandRecordForInput:[self getLocalizedKeyMapping:@"Two"] calculatorKey:EWCCalculatorTwoKey],
    [self makeKeyCommandRecordForInput:[self getLocalizedKeyMapping:@"Three"] calculatorKey:EWCCalculatorThreeKey],
    [self makeKeyCommandRecordForInput:[self getLocalizedKeyMapping:@"Four"] calculatorKey:EWCCalculatorFourKey],
    [self makeKeyCommandRecordForInput:[self getLocalizedKeyMapping:@"Five"] calculatorKey:EWCCalculatorFiveKey],
    [self makeKeyCommandRecordForInput:[self getLocalizedKeyMapping:@"Six"] calculatorKey:EWCCalculatorSixKey],
    [self makeKeyCommandRecordForInput:[self getLocalizedKeyMapping:@"Seven"] calculatorKey:EWCCalculatorSevenKey],
    [self makeKeyCommandRecordForInput:[self getLocalizedKeyMapping:@"Eight"] calculatorKey:EWCCalculatorEightKey],
    [self makeKeyCommandRecordForInput:[self getLocalizedKeyMapping:@"Nine"] calculatorKey:EWCCalculatorNineKey],
    // operators
    [self makeKeyCommandRecordForInput:[self getLocalizedKeyMapping:@"Add"] calculatorKey:EWCCalculatorAddKey],
    [self makeKeyCommandRecordForInput:[self getLocalizedKeyMapping:@"Subtract"] calculatorKey:EWCCalculatorSubtractKey],
    [self makeKeyCommandRecordForInput:[self getLocalizedKeyMapping:@"Multiply"] calculatorKey:EWCCalculatorMultiplyKey],
    [self makeKeyCommandRecordForInput:[self getLocalizedKeyMapping:@"Divide"] calculatorKey:EWCCalculatorDivideKey],
    [self makeKeyCommandRecordForInput:[self getLocalizedKeyMapping:@"Equal"] calculatorKey:EWCCalculatorEqualKey],
    [self makeKeyCommandRecordForInput:[self getLocalizedKeyMapping:@"Sign"] calculatorKey:EWCCalculatorSignKey],
    [self makeKeyCommandRecordForInput:[self getLocalizedKeyMapping:@"Percent"] calculatorKey:EWCCalculatorPercentKey],
    [self makeKeyCommandRecordForInput:[self getLocalizedKeyMapping:@"Sqrt"] calculatorKey:EWCCalculatorSqrtKey],
    // clear
    [self makeKeyCommandRecordForInput:[self getLocalizedKeyMapping:@"Clear"] calculatorKey:EWCCalculatorClearKey],
    // tax
    [self makeKeyCommandRecordForInput:[self getLocalizedKeyMapping:@"Rate"] calculatorKey:EWCCalculatorRateKey],
    [self makeKeyCommandRecordForInput:[self getLocalizedKeyMapping:@"Tax+"] calculatorKey:EWCCalculatorTaxPlusKey],
    [self makeKeyCommandRecordForInput:[self getLocalizedKeyMapping:@"Tax-"] calculatorKey:EWCCalculatorTaxMinusKey],
    // memory
    [self makeKeyCommandRecordForInput:[self getLocalizedKeyMapping:@"Memory"] calculatorKey:EWCCalculatorMemoryKey],
    [self makeKeyCommandRecordForInput:[self getLocalizedKeyMapping:@"Memory+"] calculatorKey:EWCCalculatorMemoryPlusKey],
    [self makeKeyCommandRecordForInput:[self getLocalizedKeyMapping:@"Memory-"] calculatorKey:EWCCalculatorMemoryMinusKey],
  ];

  NSMutableArray<UIKeyCommand *> *commandBuilder = [NSMutableArray<UIKeyCommand *> new];

  // add the special keys for copy/paste
  [commandBuilder addObject:[UIKeyCommand
    keyCommandWithInput:[self getLocalizedKeyMapping:@"Copy"]
    modifierFlags:UIKeyModifierCommand
    action:@selector(handleKeyCommand:)]];
  [commandBuilder addObject:[UIKeyCommand
    keyCommandWithInput:[self getLocalizedKeyMapping:@"Paste"]
    modifierFlags:UIKeyModifierCommand
    action:@selector(handleKeyCommand:)]];

  // add the regular keys
  for (EWCKeyCommandCalculatorRecord *rec in _keyMappings) {
    [commandBuilder addObject:rec.command];
  }

  // set the commands
  _keyCommands = [commandBuilder copy];

  // build the command to key mappings
  NSMutableDictionary<NSString *, NSNumber *> *mappingBuilder = [NSMutableDictionary<NSString *, NSNumber *> new];
  for (EWCKeyCommandCalculatorRecord *rec in _keyMappings) {
    mappingBuilder[rec.command.input] = @(rec.calculatorKey);
  }

  _commandToKey = [mappingBuilder copy];
}

/**
  Helper to simplifiy the allocation of regular keyboard command mappings.

  @param input The string to recognize for the keyboard input.
  @param calculatorKey The calculator key to map the input to.

  @return A mapping record of the keyboard input to the calculator key.
 */
- (EWCKeyCommandCalculatorRecord *)makeKeyCommandRecordForInput:(NSString *)input calculatorKey:(EWCCalculatorKey)calculatorKey {

  return [EWCKeyCommandCalculatorRecord
    recordWithCommand:[UIKeyCommand keyCommandWithInput:input modifierFlags:0 action:@selector(handleKeyCommand:)]
    calculatorKey:calculatorKey];
}

/**
  Handler to process hardware key input.

  @param command The event about the hardware key that was triggered.
 */
- (void)handleKeyCommand:(UIKeyCommand *)command {
  // check for copy/paste
  if ((command.modifierFlags & UIKeyModifierCommand) != 0) {
    if ([command.input isEqualToString:@"c"]) {
      [_displayArea copy:nil];
    } else if ([command.input isEqualToString:@"v"]) {
      [_displayArea paste:nil];
    }
  } else {
    // translate key input to a virtual calculator key and hand it over for processing
    EWCCalculatorKey key = [self calculatorKeyFromKeyboardCommand:command];
    [self sendKeyToCalculator:key];
  }
}

/**
  Converts an individual keyboard command to the appropriate calculator key.

  @param command The command representing the registered keyboard input.

  @return The calculator key corresponding to the input.
 */
- (EWCCalculatorKey)calculatorKeyFromKeyboardCommand:(UIKeyCommand *)command {
  NSString *input = command.input;

  return (EWCCalculatorKey)_commandToKey[input].intValue;
}

///---------------------------
/// @name Color Helper Methods
///---------------------------

/**
  The color of the tax add and deduct buttons in their non-shifted state
 */
+ (UIColor *)regularTextColor {
  return [UIColor darkGrayColor];
}

/**
 The color of the tax add and deduct buttons in their shifted state (store and recall)
 */
+ (UIColor *)shiftedTextColor {
  return [UIColor colorWithRed:.1 green:.5 blue:.7 alpha:1];
}

///------------------------------------------------
/// @name `EWCEditDelegate` Protocol Implementation
///------------------------------------------------

- (nullable NSString *)willCopyText:(NSString *)text withSender:(id)sender {
  // ignore the passed text, and just get the raw value
  NSDecimalNumber *num = _calculator.displayValue;
  text = [NSString stringWithFormat:@"%@", num];

  return text;
}

- (nullable NSString *)willPasteText:(NSString *)text withSender:(id)sender {
  // try to interpret the text as a number
  NSDecimalNumber *num = [NSDecimalNumber decimalNumberWithString:text
    locale:[NSLocale currentLocale]];

  if ([num compare:[NSDecimalNumber notANumber]] != NSOrderedSame) {
    // we got some kind of number, so update the display
    [_calculator setInput:num];
    [self updateDisplayFromCalculator];
  }

  // this will set the display value directly, so always return nil
  return nil;
}

///-----------------------
/// @name Settings Methods
///-----------------------

- (void)refreshSettings {
  NSUserDefaults *settings = [NSUserDefaults standardUserDefaults];
  [settings synchronize];
  _playKeyClicks = [settings
    boolForKey:@"play_key_clicks_preference"];
}

/**
  Check whether our settings have been loaded, using the settings bundle to fill in defaults if needed.
 */
- (void)registerDefaultPreferencesIfNeeded {

  // make sure the user defaults are current
  NSUserDefaults *settings = [NSUserDefaults standardUserDefaults];
  [settings synchronize];

  // check for a known preference
  if (! [settings objectForKey:@(s_playClicksPref)]) {
    // not found, so load the settings bundle
    NSString *bundle = [[NSBundle mainBundle]
      pathForResource:@"Settings" ofType:@"bundle"];

    // get the configured setting defaults
    NSDictionary *settingsBundle = [NSDictionary
      dictionaryWithContentsOfFile:[bundle stringByAppendingPathComponent:@"Root.plist"]];
    NSArray *defs = settingsBundle[@"PreferenceSpecifiers"];

    // for each def, add it to a dictionary of values to populate into the
    // user default
    NSMutableDictionary *defaultsToPopulate = [NSMutableDictionary new];
    for (NSDictionary *def in defs) {
      NSString *key = def[@"Key"];
      if (key) {
        defaultsToPopulate[key] = def[@"DefaultValue"];
      }
    }

    // update the user default with our defaults
    [settings registerDefaults:defaultsToPopulate];
  }
}

///---------------------
/// @name Layout Methods
///---------------------

/**
  Applies the button grid layout, which requires changing the row, column configuration and where the buttons are placed within them.
 */
- (void)layoutGrid {

  // custom callback for laying out the add key, since it it double tall.
  // it uses the same corner radius as the smaller buttons
  EWCGridCustomLayoutCallback callback = ^(UIView *view, CGRect frame, CGFloat cellWidth, CGFloat cellHeight) {

    // pick the minimum overall dimension to use for the radius calculation
    NSInteger radius = (NSInteger)((cellWidth < cellHeight) ? cellWidth : cellHeight) / 2;

    // we specifically apply this function only to the add button, so we know this
    // cast is safe to do, since it is an EWCRoundedCornerButton
    EWCRoundedCornerButton *button = (EWCRoundedCornerButton *)view;

    // update the frame with the layout supplied frame
    button.frame = frame;

    // update the corner radius with our calculated value
    button.cornerRadius = radius;
  };

  // set the gutters
  _grid.rowGutter = _currentLayout->minimumRowGutter;
  _grid.columnGutter = _currentLayout->minimumColumnGutter;

  if (_layout == EWCApplicationTallLayout) {
    // tall

    // if VoiceOver is running, announce the layout change
    if (UIAccessibilityIsVoiceOverRunning()) {
      UIAccessibilityPostNotification(
        UIAccessibilityLayoutChangedNotification,
        NSLocalizedString(@"Tall Layout",
          @"Description to announce when the calculator is in tall mode"));
    }

    // configure grid layout
    _grid.rows = 9;
    _grid.columns = 3;

    // rehome buttons
    [_grid addSubView:_allButtons[EWCCalculatorZeroKey] inRow:8 column:0];
    [_grid addSubView:_allButtons[EWCCalculatorOneKey] inRow:7 column:0];
    [_grid addSubView:_allButtons[EWCCalculatorTwoKey] inRow:7 column:1];
    [_grid addSubView:_allButtons[EWCCalculatorThreeKey] inRow:7 column:2];
    [_grid addSubView:_allButtons[EWCCalculatorFourKey] inRow:6 column:0];
    [_grid addSubView:_allButtons[EWCCalculatorFiveKey] inRow:6 column:1];
    [_grid addSubView:_allButtons[EWCCalculatorSixKey] inRow:6 column:2];
    [_grid addSubView:_allButtons[EWCCalculatorSevenKey] inRow:5 column:0];
    [_grid addSubView:_allButtons[EWCCalculatorEightKey] inRow:5 column:1];
    [_grid addSubView:_allButtons[EWCCalculatorNineKey] inRow:5 column:2];
    [_grid addSubView:_allButtons[EWCCalculatorClearKey] inRow:2 column:0];
    [_grid addSubView:_allButtons[EWCCalculatorRateKey] inRow:0 column:0];
    [_grid addSubView:_allButtons[EWCCalculatorTaxPlusKey] inRow:0 column:1];
    [_grid addSubView:_allButtons[EWCCalculatorTaxMinusKey] inRow:0 column:2];
    [_grid addSubView:_allButtons[EWCCalculatorMemoryKey] inRow:1 column:0];
    [_grid addSubView:_allButtons[EWCCalculatorMemoryPlusKey] inRow:1 column:1];
    [_grid addSubView:_allButtons[EWCCalculatorMemoryMinusKey] inRow:1 column:2];
    [_grid addSubView:_allButtons[EWCCalculatorAddKey] startingInRow:3 column:2 endingInRow:4 column:2 withLayout:callback];
    [_grid addSubView:_allButtons[EWCCalculatorSubtractKey] inRow:4 column:1];
    [_grid addSubView:_allButtons[EWCCalculatorMultiplyKey] inRow:3 column:1];
    [_grid addSubView:_allButtons[EWCCalculatorDivideKey] inRow:3 column:0];
    [_grid addSubView:_allButtons[EWCCalculatorSignKey] inRow:4 column:0];
    [_grid addSubView:_allButtons[EWCCalculatorDecimalKey] inRow:8 column:1];
    [_grid addSubView:_allButtons[EWCCalculatorPercentKey] inRow:2 column:1];
    [_grid addSubView:_allButtons[EWCCalculatorSqrtKey] inRow:2 column:2];
    [_grid addSubView:_allButtons[EWCCalculatorEqualKey] inRow:8 column:2];

  } else {
    // wide

    // if VoiceOver is running, announce the layout change
    if (UIAccessibilityIsVoiceOverRunning()) {
      UIAccessibilityPostNotification(
        UIAccessibilityLayoutChangedNotification,
        NSLocalizedString(@"Wide Layout",
          @"Description to announce when the calculator is in wide mode"));
    }

    // configure grid layout
    _grid.rows = 5;
    _grid.columns = 6;

    // rehome buttons
    [_grid addSubView:_allButtons[EWCCalculatorZeroKey] inRow:4 column:1];
    [_grid addSubView:_allButtons[EWCCalculatorOneKey] inRow:3 column:1];
    [_grid addSubView:_allButtons[EWCCalculatorTwoKey] inRow:3 column:2];
    [_grid addSubView:_allButtons[EWCCalculatorThreeKey] inRow:3 column:3];
    [_grid addSubView:_allButtons[EWCCalculatorFourKey] inRow:2 column:1];
    [_grid addSubView:_allButtons[EWCCalculatorFiveKey] inRow:2 column:2];
    [_grid addSubView:_allButtons[EWCCalculatorSixKey] inRow:2 column:3];
    [_grid addSubView:_allButtons[EWCCalculatorSevenKey] inRow:1 column:1];
    [_grid addSubView:_allButtons[EWCCalculatorEightKey] inRow:1 column:2];
    [_grid addSubView:_allButtons[EWCCalculatorNineKey] inRow:1 column:3];
    [_grid addSubView:_allButtons[EWCCalculatorClearKey] inRow:1 column:0];
    [_grid addSubView:_allButtons[EWCCalculatorRateKey] inRow:0 column:3];
    [_grid addSubView:_allButtons[EWCCalculatorTaxPlusKey] inRow:0 column:4];
    [_grid addSubView:_allButtons[EWCCalculatorTaxMinusKey] inRow:0 column:5];
    [_grid addSubView:_allButtons[EWCCalculatorMemoryKey] inRow:2 column:5];
    [_grid addSubView:_allButtons[EWCCalculatorMemoryPlusKey] inRow:4 column:5];
    [_grid addSubView:_allButtons[EWCCalculatorMemoryMinusKey] inRow:3 column:5];
    [_grid addSubView:_allButtons[EWCCalculatorAddKey] startingInRow:3 column:4 endingInRow:4 column:4 withLayout:callback];
    [_grid addSubView:_allButtons[EWCCalculatorSubtractKey] inRow:2 column:4];
    [_grid addSubView:_allButtons[EWCCalculatorMultiplyKey] inRow:1 column:4];
    [_grid addSubView:_allButtons[EWCCalculatorDivideKey] inRow:1 column:5];
    [_grid addSubView:_allButtons[EWCCalculatorSignKey] inRow:2 column:0];
    [_grid addSubView:_allButtons[EWCCalculatorDecimalKey] inRow:4 column:2];
    [_grid addSubView:_allButtons[EWCCalculatorPercentKey] inRow:3 column:0];
    [_grid addSubView:_allButtons[EWCCalculatorSqrtKey] inRow:4 column:0];
    [_grid addSubView:_allButtons[EWCCalculatorEqualKey] inRow:4 column:3];
  }
}

/**
  Calculates the leading spacing for the status indicators.
 */
- (float)getLeadingStatusConstant:(CGFloat)width {
  return 20 + width * _grid.columnGutter;
}

/**
 Calculates the trailing spacing for the status indicators.

 This used to be a different value than the leading, hence the separate function.  However, the current app design has the leading and trailing equal to one another.
*/
- (float)getTrailingStatusConstant:(CGFloat)width {
  return [self getLeadingStatusConstant:width];
}

/**
  Updates the layout of controls and font sizes based on current app dimensions.

  The main operations performed involve determine whethering to layout the button grid vertically or horizontally, adjusting all fonts, and adjusting control spacing.
 */
- (void)updateLayoutOnChange {

  // we need to take insets into account for devices with a notch
  UIEdgeInsets insets = self.view.safeAreaInsets;

  CGFloat width = self.view.bounds.size.width - insets.right - insets.left;
  CGFloat height = self.view.bounds.size.height - insets.top - insets.bottom;

  // don't do any layout if the width or height hasn't changed
  if (width == _layoutWidth && height == _layoutHeight) { return; }

  // store the dimensions to prevent relayout
  _layoutWidth = width;
  _layoutHeight = height;

  // determine whether we are in a tall or wide scenario
  EWCApplicationLayout oldLayout = _layout;
  float aspectRatio = height / width;
  _layout = (aspectRatio >= s_tallGridHeightWidthRatio)
    ? EWCApplicationTallLayout
    : EWCApplicationWideLayout;

  if (_layout == EWCApplicationWideLayout) {
    _currentLayout = (width < height) ? &s_narrowLayoutConstants : &s_wideLayoutConstants;
  } else {
    _currentLayout = &s_tallLayoutConstants;
  }

  // apply the layout if needed
  if (_layout != oldLayout) {
    [self layoutGrid];
  }

  // use the height as the dimension to base our font sizes on
  CGFloat fontDim = height;

  // get the display font size
  CGFloat fontHeight = fontDim * _currentLayout->displaySizeAsPercentOfHeight;

  // use it to update the display font size
  [_displayArea setFont:[_displayArea.font fontWithSize:fontHeight]];

  // calculate the layout properties that depend on the display font height
  CGFloat displayHeight = fontHeight * _currentLayout->displayHeightFromFontSize;
  _gridTopConstraint.constant = -height + displayHeight + _gridBottomConstraint.constant;

  // update the remaining font sizes
  [self setTextButtonsFontSize:fontDim * _currentLayout->textSizeAsPercentOfHeight];
  [self setDigitButtonsFontSize:fontDim * _currentLayout->digitSizeAsPercentOfHeight];
  [self setOperatorButtonsFontSize:fontDim * _currentLayout->operatorSizeAsPercentOfHeight];
  [self setStatusFontSize:fontDim * _currentLayout->statusSizeAsPercentOfHeight];

  // adjust the status constraints
  _statusRightConstraint.constant = [self getTrailingStatusConstant:width];
  _statusLeftConstraint.constant = [self getLeadingStatusConstant:width];
}

/**
  Applies a font size to all of the buttons in an array of buttons.

  @param points The new font size in points.
  @param buttons An array of buttons to which to apply the font size.
*/
- (void)setFontSize:(CGFloat)points forButtons:(NSArray<UIButton *> *)buttons {
  // don't update if the buttons haven't been registered yet
  if (buttons.count == 0) { return; }

  // use one of the buttons in the group to get a new font of the desired size
  UIButton *button = buttons[0];
  UIFont *font = [button.titleLabel.font fontWithSize:points];

  // apply the new font to each of the buttons
  for (UIButton *button in buttons) {
    [button.titleLabel setFont:font];
  }
}

/**
  Applies a font size to all of the text and sub operator buttons.

  @param points The new font size in points.
*/
- (void)setTextButtonsFontSize:(CGFloat)points {
  [self setFontSize:points forButtons:_textButtons];
}

/**
  Applies a font size to all of the digit buttons.

  @param points The new font size in points.
*/
- (void)setDigitButtonsFontSize:(CGFloat)points {
  [self setFontSize:points forButtons:_digitButtons];
}

/**
  Applies a font size to all of the main operator buttons.

  @param points The new font size in points.
*/
- (void)setOperatorButtonsFontSize:(CGFloat)points {
  [self setFontSize:points forButtons:_opButtons];

  // apply an inset to compensate for the operators not being vertically
  // centered within its font height.  This inset moves the label up slightly.
  UIEdgeInsets inset = UIEdgeInsetsMake(0, 0, points * 0.200, 0);

  for (UIButton *button in _opButtons) {
    [button setTitleEdgeInsets:inset];
  }
}

/**
  Applies a font size to all of the status indicators.

  @param points The new font size in points.
 */
- (void)setStatusFontSize:(CGFloat)points {
  UILabel *label = _statusLabels[0];
  UIFont *font = [label.font fontWithSize:points];
  for (UILabel *label in _statusLabels) {
    label.font = font;
  }
}

///-----------------------------------------
/// @name Button Construction Helper Methods
///-----------------------------------------

/**
  Creates a main operator (e.g. +) `EWCRoundedCornerButton` for use in our grid layout.

  @param label The label to display on the button.
  @param accessibilityLabel The accessibility label to apply to the button for VoiceOver.
  @param tag The tag of the button, which in practice, stores the `EWCCalculatorKey` of the button.
  @param width The narrow dimension of the current layout, used to determine the label font size.

  @return A main operator button for adding to our `EWCGridLayoutView`.
*/
- (EWCRoundedCornerButton *)makeMainOperatorButton:(NSString *)label
  accessibilityLabel:(NSString *)accessibilityLabel
  tag:(NSInteger)tag
  forWidth:(float)width {

  return [self makeOperatorButton:label
    accessibilityLabel:accessibilityLabel
    tag:tag
    withSize:_currentLayout->operatorSizeAsPercentOfHeight * width];
}

/**
  Creates a sub operator (e.g. %) `EWCRoundedCornerButton` for use in our grid layout.

  @param label The label to display on the button.
  @param accessibilityLabel The accessibility label to apply to the button for VoiceOver.
  @param tag The tag of the button, which in practice, stores the `EWCCalculatorKey` of the button.
  @param width The narrow dimension of the current layout, used to determine the label font size.

  @return A sub operator button for adding to our `EWCGridLayoutView`.
*/
- (EWCRoundedCornerButton *)makeSubOperatorButton:(NSString *)label
  accessibilityLabel:(NSString *)accessibilityLabel
  tag:(NSInteger)tag
  forWidth:(float)width {

  return [self makeOperatorButton:label
    accessibilityLabel:accessibilityLabel
    tag:tag
    withSize:_currentLayout->textSizeAsPercentOfHeight * width];
}

/**
  Creates an operator (e.g. +) `EWCRoundedCornerButton` for use in our grid layout.

  @param label The label to display on the button.
  @param accessibilityLabel The accessibility label to apply to the button for VoiceOver.
  @param tag The tag of the button, which in practice, stores the `EWCCalculatorKey` of the button.
  @param points The size of the label font in points.  There are main and sub operations, and they use different sizes, but they share the same coloration.

  @return An operator button for adding to our `EWCGridLayoutView`.
*/
- (EWCRoundedCornerButton *)makeOperatorButton:(NSString *)label
  accessibilityLabel:(NSString *)accessibilityLabel
  tag:(NSInteger)tag
  withSize:(float)points {

  return [self makeCalculatorButtonWithLabel:label
    accessibilityLabel:accessibilityLabel
    tag:tag
    colored:[UIColor whiteColor]
    highlightColor:[UIColor colorWithRed:1.0 green:204.0/255 blue:136.0/255 alpha:1.0]
    backgroundColor:[UIColor orangeColor]
    fontSize:points];
}

/**
  Creates a digit `EWCRoundedCornerButton` for use in our grid layout.

  @param label The label to display on the button.
  @param accessibilityLabel The accessibility label to apply to the button for VoiceOver.
  @param tag The tag of the button, which in practice, stores the `EWCCalculatorKey` of the button.
  @param width The narrow dimension of the current layout, used to determine the label font size.

  @return A digit button for adding to our `EWCGridLayoutView`.
*/
- (EWCRoundedCornerButton *)makeDigitButton:(NSString *)label
  accessibilityLabel:(NSString *)accessibilityLabel
  tag:(NSInteger)tag
  forWidth:(float)width {

  return [self makeCalculatorButtonWithLabel:label
    accessibilityLabel:accessibilityLabel
    tag:tag
    colored:[UIColor whiteColor]
    highlightColor:[UIColor lightGrayColor]
    backgroundColor:[UIColor darkGrayColor]
    fontSize:_currentLayout->digitSizeAsPercentOfHeight * width];
}

/**
  Creates a text (e.g. mrc) `EWCRoundedCornerButton` for use in our grid layout.

  @param label The label to display on the button.
  @param accessibilityLabel The accessibility label to apply to the button for VoiceOver.
  @param tag The tag of the button, which in practice, stores the `EWCCalculatorKey` of the button.
  @param width The narrow dimension of the current layout, used to determine the label font size.

  @return A text button for adding to our `EWCGridLayoutView`.
*/
- (EWCRoundedCornerButton *)makeTextButton:(NSString *)label
  accessibilityLabel:(NSString *)accessibilityLabel
  tag:(NSInteger)tag
  forWidth:(float)width {

  return [self makeCalculatorButtonWithLabel:label
    accessibilityLabel:accessibilityLabel
    tag:tag
    colored:[ViewController regularTextColor]
    highlightColor:[UIColor colorWithRed:204.0/255 green:204.0/255 blue:204.0/255 alpha:1.0]
    backgroundColor:[UIColor lightGrayColor]
    fontSize:_currentLayout->textSizeAsPercentOfHeight * width];
}

/**
  Creates a general `EWCRoundedCornerButton` for use in our grid layout.

  @param label The label to display on the button.
  @param accessibilityLabel The accessibility label to apply to the button for VoiceOver.
  @param tag The tag of the button, which in practice, stores the `EWCCalculatorKey` of the button.
  @param color The color of the text in the button.
  @param highlightColor The color of the button background when highlighted (when there is a touch over the button).
  @param backgroundColor The color of the button background under usual conditions.
  @param fontSize The size of the font in points (the system font is used).

  @return A button suitable for adding to our `EWCGridLayoutView`.
 */
- (EWCRoundedCornerButton *)makeCalculatorButtonWithLabel:(NSString *)label
  accessibilityLabel:(NSString *)accessibilityLabel
  tag:(NSInteger)tag
  colored:(UIColor *)color
  highlightColor:(UIColor *)highlightColor
  backgroundColor:(UIColor *)backgroundColor
  fontSize:(CGFloat)fontSize {

  EWCRoundedCornerButton *button = [EWCRoundedCornerButton buttonLabeled:label
    colored:color
    backgroundColor:backgroundColor];
  button.accessibilityLabel = accessibilityLabel;
  button.highlightedBackgroundColor = highlightColor;
  button.titleLabel.font = [UIFont systemFontOfSize:fontSize];
  button.tag = tag;
  [button addTarget:self
    action:@selector(onCalculatorButtonPressed:forEvent:)
    forControlEvents:UIControlEventTouchUpInside];

  return button;
}

///---------------------------
/// @name Button Press Handler
///---------------------------

/**
  Callback method that forwards a UI touch event to a calculator input.
 */
- (void)onCalculatorButtonPressed:(UIButton *)sender forEvent:(UIEvent *)event {
  EWCCalculatorKey key = (EWCCalculatorKey)sender.tag;
  [self sendKeyToCalculator:key];
}

/**
  Callback for when user wants to backspace a digit.
*/
- (void)onBackspacePressed {
  [self sendKeyToCalculator:EWCCalculatorBackspaceKey];
}

/**
  Entry point for playing a sound for the pressed key.

  @param key The key that was pressed.
 */
- (void)playSoundForKey:(EWCCalculatorKey)key {
  if (_playKeyClicks) {
    EWCAudio *audio = [EWCAudio new];
    [audio config];
    AVAudioPlayer *player = [self ensureSoundIdForKey:key];
    player.volume = s_soundVolume;
    [player play];
    [_players addObject:player];
  }
}

/**
  Play an appropriate sound for a key, and sends the key to the calculator.

  @param key The key to send to the calculator.
 */
- (void)sendKeyToCalculator:(EWCCalculatorKey)key {
  [self playSoundForKey:key];
  [_calculator pressKey:key];
}

/**
  Gets the audio player for the sound of the pressed key.

  @param key The key that was pressed.

  @return An audio player instance that can be used to play the appropriate key sound.
 */
- (AVAudioPlayer *)ensureSoundIdForKey:(EWCCalculatorKey)key {
  // get the file reference for the key
  NSData *data;
  AVAudioPlayer * player;

  [self cleanupSounds];

  // figure out the source file and player var
  switch (key) {
    case EWCCalculatorRateKey:
      data = _modifyData;
      break;

    case EWCCalculatorClearKey:
    case EWCCalculatorBackspaceKey:
      data = _deleteData;
      break;

    default:
      data = _clickData;
  }

  player = [[AVAudioPlayer alloc] initWithData:data error:nil];

  return player;
}

/**
 Makes sure that we only keep references to sounds that are still active.
 */
- (void)cleanupSounds {
  NSPredicate *selector = [NSPredicate predicateWithBlock:^ BOOL (id  _Nullable evaluatedObject, NSDictionary<NSString *,id> * _Nullable bindings) {
    AVAudioPlayer *player = evaluatedObject;
    return player.playing;
  }];

  NSMutableArray<AVAudioPlayer *> *playing = [[_players
    filteredArrayUsingPredicate:selector] mutableCopy];

  _players = playing;
}

///---------------------------------
/// @name VoiceOver Dispatch Helpers
///---------------------------------

/**
  Performs a VoiceOver announcement using the accessibility label in the supplied `UIView`.

  Since we use this for status indicator announcements it won't queue the announcment, since we want it to interrupt reannouncing the current control to draw attention to itself.

  @param view The view from which to get the announcement label.  Generally, a status indicator.
 */
- (void)dispatchAnnouncementForView:(UIView *)view {
  [self dispatchAnnouncement:view.accessibilityLabel];
}

/**
  Performs a VoiceOver announcement using the supplied message.

  @param message The message to announce.  Either a `NSString` or `NSAttributedString` which can carry information about queuing.
 */
- (void)dispatchAnnouncement:(id)message {

  // don't do anything is VoiceOver isn't active
  if (! UIAccessibilityIsVoiceOverRunning()) { return; }

  double delayInSeconds = 0.75;
  dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW,
    (int64_t)(delayInSeconds * NSEC_PER_SEC));

  // dispatch to announce after a brief delay so that we don't get cut off by
  // the system reannouncing the currently selected button
  dispatch_after(popTime, dispatch_get_main_queue(), ^(void) {
    UIAccessibilityPostNotification(
    UIAccessibilityAnnouncementNotification,
    message);
  });
}

///------------------------------------------------------
/// @name Methods to Update Display State from Calculator
///------------------------------------------------------

/**
  Updates all portions of the interface that can change based on the calculator state.
 */
- (void)updateDisplayFromCalculator {
  [self updateStatusIndicators];
  [self updateDisplay];
  [self updateClearLabels];
  [self updateTaxLabels];
  [self updateMemoryLabels];
}

/**
  Updates the clear button label and accessibility label based on whether the calculator is in an error state.
 */
- (void)updateClearLabels {
  NSString *label = (_calculator.hasError)
    ? NSLocalizedString(@"All Clear Button", @"voiceover label for the clear button when there is an error")
    : NSLocalizedString(@"Clear Button", @"");
  NSString *ariaLabel = (_calculator.hasError)
    ? NSLocalizedString(@"All Clear Aria Label", @"voiceover label for the clear button when there is an error")
    : NSLocalizedString(@"Clear Aria Label", @"");
  [_clearButton setTitle:label forState:UIControlStateNormal];
  _clearButton.accessibilityLabel = ariaLabel;
}

/**
  Updates the label and accessibility label for the rate and tax buttons in response to state changes in the calculator model.
 */
- (void)updateTaxLabels {
  NSString *label;
  NSString *ariaLabel;

  ariaLabel = (_calculator.isRateShifted)
    ? NSLocalizedString(@"Rate Store Mode Aria Label", @"voiceover label for when the rate button selected store and recall")
    : NSLocalizedString(@"Rate Tax Mode Aria Label", @"");
  _rateButton.accessibilityLabel = ariaLabel;

  label = (_calculator.isRateShifted)
    ? NSLocalizedString(@"Store Button", @"label for storing a new tax rate")
    : NSLocalizedString(@"Tax+ Button", @"");
  ariaLabel = (_calculator.isRateShifted)
    ? NSLocalizedString(@"Store Aria Label", @"voiceover label for storing a new tax rate")
    : NSLocalizedString(@"Tax+ Aria Label", @"");
  [_taxPlusButton setTitle:label forState:UIControlStateNormal];
  _taxPlusButton.accessibilityLabel = ariaLabel;

  label = (_calculator.isRateShifted)
    ? NSLocalizedString(@"Recall Button", @"label for reviewing the current tax rate")
    : NSLocalizedString(@"Tax- Button", @"");
  ariaLabel = (_calculator.isRateShifted)
    ? NSLocalizedString(@"Recall Aria Label", @"voiceover label for reviewing the current tax rate")
    : NSLocalizedString(@"Tax- Aria Label", @"");
  [_taxMinusButton setTitle:label forState:UIControlStateNormal];
  _taxMinusButton.accessibilityLabel = ariaLabel;

  UIColor *taxColor = (_calculator.isRateShifted)
    ? [ViewController shiftedTextColor]
    : [ViewController regularTextColor];

  [_taxPlusButton setTitleColor:taxColor forState:UIControlStateNormal];
  [_taxMinusButton setTitleColor:taxColor forState:UIControlStateNormal];
}

/**
  Updates the accessibility label on the memory (mrc) button in response to the action it will take.
 */
- (void)updateMemoryLabels {
  NSString *ariaLabel = (_calculator.shouldMemoryClear && _calculator.hasMemory)
    ? NSLocalizedString(@"Memory Clear Aria Label", @"voiceover label for the memory button when it should clear")
    : NSLocalizedString(@"Memory Recall Aria Label", @"voiceover label for the memory button when it should recall");
  _memoryButton.accessibilityLabel = ariaLabel;
}

/**
  Updates the displayed value based on the calculator model state.  State changes also trigger VoiceOver announcements.
 */
- (void)updateDisplay {

  // get the values from the calculator
  NSString *lastDisplay = _displayArea.text;
  NSString *newDisplay = _calculator.displayContent;

  // update the display and accessibility labels
  [_displayArea setText:newDisplay];
  _displayArea.accessibilityLabel = _calculator.displayAccessibleContent;

  // if there was a change, make an announcement
  if ([lastDisplay compare:newDisplay] != NSOrderedSame) {

    NSString *accesssibleDisplay = _calculator.displayAccessibleContent;

    // add an attribute to the message to not interrupt the current announcement.
    // this doesn't maintain a full queue, it only applies to the current message,
    // so we still have to try to avoid starting another message before this
    // one gets a chance to play
    NSAttributedString *message = [[NSAttributedString alloc]
      initWithString:accesssibleDisplay
      attributes:@{ UIAccessibilitySpeechAttributeQueueAnnouncement: @1 }];

    [self dispatchAnnouncement:message];
  }
}

/**
  Updates the visibility of the status indicators based on the calculator model state.  State changes also trigger VoiceOver announcements.
 */
- (void)updateStatusIndicators {

  self.errorVisible = _calculator.hasError;
  BOOL oldMemory = self.isMemoryVisible;
  self.memoryVisible = _calculator.hasMemory;
  BOOL oldTax = self.isTaxVisible;
  self.taxVisible = _calculator.isTaxStatusVisible;
  BOOL oldTaxPlus = self.isTaxPlusVisible;
  self.taxPlusVisible = _calculator.isTaxPlusStatusVisible;
  BOOL oldTaxMinus = self.isTaxMinusVisible;
  self.taxMinusVisible = _calculator.isTaxMinusStatusVisible;
  BOOL oldTaxPercent = self.isTaxPercentVisible;
  self.taxPercentVisible = _calculator.isTaxPercentStatusVisible;

  // an error status trumps everything else.
  // only check for other status changes if there is no error.
  // the other checks should also only announce if there was a change,
  // while error announces whenever it is visibile.

  if (_calculator.hasError) {
    [self dispatchAnnouncementForView:_errorIndicator];
  } else {
    if (self.isMemoryVisible && oldMemory != self.isMemoryVisible) {
      [self dispatchAnnouncementForView:_memoryIndicator];
    }
    if (self.isTaxVisible && oldTax != self.isTaxVisible) {
      [self dispatchAnnouncementForView:_taxIndicator];
    }
    if (self.isTaxPlusVisible && oldTaxPlus != self.isTaxPlusVisible) {
      [self dispatchAnnouncementForView:_taxPlusIndicator];
    }
    if (self.isTaxMinusVisible && oldTaxMinus != self.isTaxMinusVisible) {
      [self dispatchAnnouncementForView:_taxMinusIndicator];
    }
    if (self.isTaxPercentVisible && oldTaxPercent != self.isTaxPercentVisible) {
      [self dispatchAnnouncementForView:_taxPercentIndicator];
    }
  }
}

@end
