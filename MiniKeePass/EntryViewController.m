/*
 * Copyright 2011 Jason Rush and John Flanagan. All rights reserved.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#import "EntryViewController.h"
#import "Kdb4Node.h"

#import <MBProgressHUD/MBProgressHUD.h>

#define SECTION_HEADER_HEIGHT 46.0f

@interface EntryViewController() {
    MiniKeePassAppDelegate *appDelegate;
    TitleFieldCell *titleCell;
    TextFieldCell *usernameCell;
    PasswordFieldCell *passwordCell;
    UrlFieldCell *urlCell;
    TextViewCell *commentsCell;
    
    NSArray *defaultCells;
    
    BOOL canceled;
}

@property (nonatomic) BOOL isKdb4;
@property (nonatomic, retain) NSMutableArray *editingStringFields;
@property (nonatomic, readonly) NSArray *currentStringFields;

@end

@implementation EntryViewController

- (id)initWithStyle:(UITableViewStyle)style {
    self = [super initWithStyle:style];
    if (self) {
        self.tableView.delaysContentTouches = YES;
        self.tableView.allowsSelectionDuringEditing = YES;

        self.navigationItem.rightBarButtonItem = self.editButtonItem;
        
        appDelegate = (MiniKeePassAppDelegate*)[[UIApplication sharedApplication] delegate];
        
        titleCell = [[TitleFieldCell alloc] init];
        titleCell.textLabel.text = NSLocalizedString(@"Title", nil);
        titleCell.textField.placeholder = NSLocalizedString(@"Title", nil);
        titleCell.textField.enabled = NO;
        titleCell.textFieldCellDelegate = self;
        titleCell.imageButton.adjustsImageWhenHighlighted = NO;
        [titleCell.imageButton addTarget:self action:@selector(imageButtonPressed) forControlEvents:UIControlEventTouchUpInside];
        
        usernameCell = [[TextFieldCell alloc] init];
        usernameCell.textLabel.text = NSLocalizedString(@"Username", nil);
        usernameCell.textField.placeholder = NSLocalizedString(@"Username", nil);
        usernameCell.textField.enabled = NO;
        usernameCell.textField.autocorrectionType = UITextAutocorrectionTypeNo;
        usernameCell.textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        usernameCell.textFieldCellDelegate = self;
        
        passwordCell = [[PasswordFieldCell alloc] init];
        passwordCell.textLabel.text = NSLocalizedString(@"Password", nil);
        passwordCell.textField.placeholder = NSLocalizedString(@"Password", nil);
        passwordCell.textField.enabled = NO;
        passwordCell.textFieldCellDelegate = self;
        [passwordCell.accessoryButton addTarget:self action:@selector(showPasswordPressed) forControlEvents:UIControlEventTouchUpInside];
        [passwordCell.editAccessoryButton addTarget:self action:@selector(generatePasswordPressed) forControlEvents:UIControlEventTouchUpInside];
        
        urlCell = [[UrlFieldCell alloc] init];
        urlCell.textLabel.text = NSLocalizedString(@"URL", nil);
        urlCell.textField.placeholder = NSLocalizedString(@"URL", nil);
        urlCell.textField.enabled = NO;
        urlCell.textFieldCellDelegate = self;
        urlCell.textField.returnKeyType = UIReturnKeyDone;
        [urlCell.accessoryButton addTarget:self action:@selector(openUrlPressed) forControlEvents:UIControlEventTouchUpInside];
        
        defaultCells = [@[titleCell, usernameCell, passwordCell, urlCell] retain];
        
        commentsCell = [[TextViewCell alloc] init];
        commentsCell.textView.editable = NO;
    }
    return self;
}

- (void)dealloc {
    [titleCell release];
    [usernameCell release];
    [passwordCell release];
    [urlCell release];
    [commentsCell release];
    [defaultCells release];
    [_entry release];

    [super dealloc];
}

- (void)viewDidLoad {
    self.tableView.sectionHeaderHeight = 0.0f;
    self.tableView.sectionFooterHeight = 0.0f;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    // Mark the view as not being canceled
    canceled = NO;
    
    // Add listeners to the keyboard
    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    [notificationCenter addObserver:self selector:@selector(applicationWillResignActive:) name:UIApplicationWillResignActiveNotification object:nil];
    
    if (self.isNewEntry) {
        [self setEditing:YES animated:NO];
        self.isNewEntry = NO;
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    
    // Remove listeners from the keyboard
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)applicationWillResignActive:(id)sender {
    // Resign first responder to prevent password being in sight and UI glitchs
    [titleCell.textField resignFirstResponder];
    [usernameCell.textField resignFirstResponder];
    [passwordCell.textField resignFirstResponder];
    [urlCell.textField resignFirstResponder];
    [commentsCell.textView resignFirstResponder];
}

- (void)setEntry:(KdbEntry *)e {
    [_entry release];
    
    _entry = [e retain];
    self.isKdb4 = [self.entry isKindOfClass:[Kdb4Entry class]];
    
    // Update the fields
    self.title = self.entry.title;
    titleCell.textField.text = self.entry.title;
    [self setSelectedImageIndex:self.entry.image];
    usernameCell.textField.text = self.entry.username;
    passwordCell.textField.text = self.entry.password;
    urlCell.textField.text = self.entry.url;
    commentsCell.textView.text = self.entry.notes;
}

- (NSArray *)currentStringFields {
    if (!self.isKdb4) {
        return nil;
    }

    if (self.editing) {
        return self.editingStringFields;
    } else {
        return ((Kdb4Entry *)self.entry).stringFields;
    }
}

- (void)cancelPressed {
    canceled = YES;
    [self setEditing:NO animated:YES];
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
    if (titleCell.textField.text.length <= 0) {
        NSString *title = NSLocalizedString(@"Title cannot be empty", nil);
        UIAlertView  *alertView = [[[UIAlertView alloc] initWithTitle:title message:nil delegate:nil cancelButtonTitle:@"Ok" otherButtonTitles:nil] autorelease];
        [alertView show];
        return;
    }

    // Ensure that all updates happen at once
    [self.tableView beginUpdates];

    [super setEditing:editing animated:animated];
    
    // Save the database or reset the entry
    if (editing == NO && !canceled) {
        self.entry.title = titleCell.textField.text;
        self.entry.image = self.selectedImageIndex;
        self.entry.username = usernameCell.textField.text;
        self.entry.password = passwordCell.textField.text;
        self.entry.url = urlCell.textField.text;
        self.entry.notes = commentsCell.textView.text;

        // Save string fields
        if (self.isKdb4) {
            // Ensure any textfield currently being edited is saved
            int count = self.editingStringFields.count;
            for (int i = 0; i < count; i++) {
                TextFieldCell *cell = (TextFieldCell *)[self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:i inSection:1]];
                [cell.textField resignFirstResponder];
            }

            Kdb4Entry *kdb4Entry = (Kdb4Entry *)self.entry;
            [kdb4Entry.stringFields removeAllObjects];
            [kdb4Entry.stringFields addObjectsFromArray:self.editingStringFields];
            self.editingStringFields = nil;
        }

        appDelegate.databaseDocument.dirty = YES;
        
        // Save the database document
        [appDelegate.databaseDocument save];
    } else if (canceled) {
        [self setEntry:self.entry];
    }

    // Index paths for cells to be added or removed
    NSMutableArray *paths = [NSMutableArray arrayWithCapacity:3];

    // Manage default cells
    for (TextFieldCell *cell in defaultCells) {
        cell.textField.enabled = editing;

        // Add empty cells to the list of cells that need to be added when editing
        if (cell.textField.text.length == 0) {
            [paths addObject:[NSIndexPath indexPathForRow:[defaultCells indexOfObject:cell] inSection:0]];
        }
    }
    commentsCell.textView.editable = editing;

    // Manage custom field cells
    if (self.isKdb4) {
        NSArray *stringFields = ((Kdb4Entry *)self.entry).stringFields;
        int count = stringFields.count;
        if (editing) {
            self.editingStringFields = [[[NSMutableArray alloc] initWithArray:stringFields copyItems:YES] autorelease];
        }

        // Reset the custom string cells
        for (int i = 0; i < count; i++) {
            TextFieldCell *cell = (TextFieldCell *)[self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:i inSection:1]];
            [cell.textField resignFirstResponder];
            cell.textField.enabled = editing;
            cell.showGrayBar = editing;
        }

        if (count == 0) {
            // Special case where Custom section was not/will not be visable
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationFade];
        } else {
            // Add New cell added to list of cells to update
            [paths addObject:[NSIndexPath indexPathForRow:count inSection:1]];
        }
    }

    if (editing) {
        UIBarButtonItem *cancelButton = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Cancel", nil) style:UIBarButtonItemStylePlain target:self action:@selector(cancelPressed)];
        self.navigationItem.leftBarButtonItem = cancelButton;
        [cancelButton release];

        titleCell.selectionStyle = UITableViewCellSelectionStyleNone;
        usernameCell.selectionStyle = UITableViewCellSelectionStyleNone;
        passwordCell.selectionStyle = UITableViewCellSelectionStyleNone;
        urlCell.selectionStyle = UITableViewCellSelectionStyleNone;

        titleCell.imageButton.adjustsImageWhenHighlighted = YES;
        canceled = NO;

        [self.tableView insertRowsAtIndexPaths:paths withRowAnimation:UITableViewRowAnimationTop];
    } else {
        self.navigationItem.leftBarButtonItem = nil;
        
        [titleCell.textField resignFirstResponder];
        [usernameCell.textField resignFirstResponder];
        [passwordCell.textField resignFirstResponder];
        [urlCell.textField resignFirstResponder];
        [commentsCell.textView resignFirstResponder];

        titleCell.selectionStyle = UITableViewCellSelectionStyleBlue;
        usernameCell.selectionStyle = UITableViewCellSelectionStyleBlue;
        passwordCell.selectionStyle = UITableViewCellSelectionStyleBlue;
        urlCell.selectionStyle = UITableViewCellSelectionStyleBlue;

        titleCell.imageButton.adjustsImageWhenHighlighted = NO;

        [self.tableView deleteRowsAtIndexPaths:paths withRowAnimation:UITableViewRowAnimationTop];
    }

    // Commit all updates
    [self.tableView endUpdates];
}

- (void)textFieldCellWillReturn:(TextFieldCell *)textFieldCell {
    NSIndexPath *indexPath = [self.tableView indexPathForCell:textFieldCell];

    switch (indexPath.section) {
        case 0: {
            if (textFieldCell == titleCell) {
                [usernameCell.textField becomeFirstResponder];
            } else if (textFieldCell == usernameCell) {
                [passwordCell.textField becomeFirstResponder];
            } else if (textFieldCell == passwordCell) {
                [urlCell.textField becomeFirstResponder];
            } else if (textFieldCell == urlCell) {
                [self setEditing:NO animated:YES];
            }
            break;
        }
        case 1: {
            [textFieldCell.textField resignFirstResponder];
        }
        default:
            break;
    }
}

- (void)textFieldCellDidEndEditing:(TextFieldCell *)textFieldCell {
    NSIndexPath *indexPath = [self.tableView indexPathForCell:textFieldCell];

    switch (indexPath.section) {
        case 1: {
            StringField *stringField = [self.editingStringFields objectAtIndex:indexPath.row];
            stringField.value = textFieldCell.textField.text;
            break;
        }
        default:
            break;
    }
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    int filledCells = 1; // Title is always filled out

    switch (section) {
        case 0:
            if (tableView.isEditing) {
                return [defaultCells count];
            }
            
            for (TextFieldCell* cell in @[usernameCell, passwordCell, urlCell]) {
                if (cell.textField.text.length > 0) {
                    filledCells++;
                }
            }
            
            return filledCells;
        case 1:
            if (self.isKdb4) {
                int numCells = self.currentStringFields.count;
                // Additional cell for Add cell
                return self.editing ? numCells + 1 : numCells;
            } else {
                return 0;
            }
        case 2:
            return 1;
    }
    
    return 0;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case 0:
            break;
        case 1: {
            switch (editingStyle) {
                case UITableViewCellEditingStyleInsert:
                    [self addPressed];
                    break;
                case UITableViewCellEditingStyleDelete: {
                    [self.editingStringFields removeObjectAtIndex:indexPath.row];
                    [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationBottom];
                    break;
                }
                default:
                    break;
            }
            break;
        }
        case 2:
            break;
    }
}

- (void)addPressed {
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:self.editingStringFields.count inSection:1];
    [self.editingStringFields addObject:[StringField stringFieldWithKey:@"Name" andValue:@""]];
    [self.tableView insertRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationBottom];
}

# pragma mark - Table view delegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case 0:
        case 1:
            return 40;
        case 2:
            return 104;
    }
    
    return 40;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0:
            return nil;
        case 1:
            if (self.isKdb4) {
                if ([self tableView:tableView numberOfRowsInSection:1] > 0) {
                    return NSLocalizedString(@"Custom Fields", nil);
                } else {
                    return nil;
                }
            } else {
                return nil;
            }
        case 2:
            return NSLocalizedString(@"Comments", nil);
    }
    
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    // Special case for top section with no section title
    if (section == 0) {
        return 10.0f;
    }
    
    return [self tableView:tableView titleForHeaderInSection:section] == nil ? 0.0f : SECTION_HEADER_HEIGHT;;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case 0:
            return UITableViewCellEditingStyleNone;
        case 1:
            if (self.isKdb4) {
                if (indexPath.row < self.currentStringFields.count) {
                    return UITableViewCellEditingStyleDelete;
                } else {
                    return UITableViewCellEditingStyleInsert;
                }
            }
            return UITableViewCellEditingStyleNone;
        case 2:
            return UITableViewCellEditingStyleNone;
    }
    return UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 1) {
        return YES;
    } else {
        return NO;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *TextFieldCellIdentifier = @"TextFieldCell";
    static NSString *AddFieldCellIdentifier = @"AddFieldCell";
    switch (indexPath.section) {
        case 0: {
            switch (indexPath.row) {
                case 0:
                    return titleCell;
                case 1:
                    if ((tableView.isEditing || usernameCell.textField.text.length > 0) && [usernameCell superview] == nil) {
                        return usernameCell;
                    }
                case 2:
                    if ((tableView.isEditing || passwordCell.textField.text.length > 0) && [passwordCell superview] == nil) {
                        return passwordCell;
                    }
                case 3:
                    return urlCell;
            }
        }
        case 1: {
            if (indexPath.row == self.currentStringFields.count) {
                // Return "Add new..." cell
                UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:AddFieldCellIdentifier];
                if (cell == nil) {
                    cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue2 reuseIdentifier:AddFieldCellIdentifier] autorelease];
                    cell.textLabel.textAlignment = NSTextAlignmentLeft;
                    cell.textLabel.text = @"Add new...";

                    // Add new cell when this cell is tapped
                    [cell addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(addPressed)] autorelease]];
                }

                return cell;
            } else {
                TextFieldCell *cell = [tableView dequeueReusableCellWithIdentifier:TextFieldCellIdentifier];
                if (cell == nil) {
                    cell = [[[TextFieldCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:TextFieldCellIdentifier] autorelease];
                    cell.textFieldCellDelegate = self;
                    cell.textField.returnKeyType = UIReturnKeyDone;
                }

                StringField *stringField = [self.currentStringFields objectAtIndex:indexPath.row];
                [cell setShowGrayBar:self.editing];

                cell.textLabel.text = stringField.key;
                cell.textField.text = stringField.value;
                cell.textField.enabled = self.editing;

                return cell;
            }
        }
        case 2: {
            return commentsCell;
        }
    }
    
    return nil;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.editing) {
        if (indexPath.section != 1) {
            return;
        }

        StringField *stringField = [self.editingStringFields objectAtIndex:indexPath.row];
        SelectLabelViewController *slvc = [[SelectLabelViewController alloc] initWithStyle:UITableViewStyleGrouped];
        slvc.object = indexPath;
        [slvc setCurrentLabel:stringField.key];
        slvc.delegate = self;

        UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:slvc];
        [slvc release];

        [self.navigationController presentViewController:navController animated:YES completion:nil];
        [navController release];

        return;
    }

    tableView.allowsSelection = NO;
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    TextFieldCell *cell = (TextFieldCell *)[tableView cellForRowAtIndexPath:indexPath];
    pasteboard.string = cell.textField.text;
    
    // Figure out frame for copied label
    NSString *copiedString = NSLocalizedString(@"Coppied", nil);
    UIFont *font = [UIFont boldSystemFontOfSize:18];
    CGSize size = [copiedString sizeWithFont:font];
    CGFloat x = (cell.frame.size.width - size.width) / 2.0;
    CGFloat y = (cell.frame.size.height - size.height) / 2.0;
    
    // Contruct label
    UILabel *copiedLabel = [[UILabel alloc] initWithFrame:CGRectMake(x, y, size.width, size.height)];
    copiedLabel.text = copiedString;
    copiedLabel.font = font;
    copiedLabel.textAlignment = UITextAlignmentCenter;
    copiedLabel.textColor = [UIColor whiteColor];
    copiedLabel.backgroundColor = [UIColor clearColor];

    // Put cell into "Copied" state
    [cell addSubview:copiedLabel];
    cell.textField.alpha = 0;
    cell.textLabel.alpha = 0;
    cell.accessoryView.hidden = YES;

    int64_t delayInSeconds = 1.0;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        [UIView animateWithDuration:0.5 animations:^{
            // Return to normal state
            copiedLabel.alpha = 0;
            cell.textField.alpha = 1;
            cell.textLabel.alpha = 1;
            [cell setSelected:NO animated:YES];
        } completion:^(BOOL finished) {
            cell.accessoryView.hidden = NO;
            [copiedLabel removeFromSuperview];
            [copiedLabel release];
            tableView.allowsSelection = YES;
        }];
    });
}

#pragma mark - Select label delegate

- (void)selectionLabelViewController:(SelectLabelViewController *)controller selectedLabel:(NSString *)label forObject:(id)object {
    NSIndexPath *indexPath = object;
    StringField *stringField = [self.editingStringFields objectAtIndex:indexPath.row];
    stringField.key = label;

    TextFieldCell *cell = (TextFieldCell *)[self.tableView cellForRowAtIndexPath:indexPath];
    cell.textLabel.text = label;

    [controller dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Image related

- (void)setSelectedImageIndex:(NSUInteger)index {
    _selectedImageIndex = index;

    [titleCell.imageButton setImage:[appDelegate loadImage:index] forState:UIControlStateNormal];
}

- (void)imageButtonPressed {
    if (self.tableView.isEditing) {
        ImagesViewController *imagesViewController = [[ImagesViewController alloc] init];
        imagesViewController.delegate = self;
        [imagesViewController setSelectedImage:self.selectedImageIndex];
        [self.navigationController pushViewController:imagesViewController animated:YES];
        [imagesViewController release];
    }
}

- (void)imagesViewController:(ImagesViewController *)controller imageSelected:(NSUInteger)index {
    [self setSelectedImageIndex:index];
}

#pragma mark - Password Display

- (void)showPasswordPressed {
	MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.navigationController.view animated:YES];

	hud.mode = MBProgressHUDModeText;
    hud.detailsLabelText = self.entry.password;
    hud.detailsLabelFont = [UIFont fontWithName:@"Andale Mono" size:24];
	hud.margin = 10.f;
	hud.removeFromSuperViewOnHide = YES;
    [hud addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:hud action:@selector(hide:)] autorelease]];
}

#pragma mark - Password Generation

- (void)generatePasswordPressed {
    PasswordGeneratorViewController *passwordGeneratorViewController = [[PasswordGeneratorViewController alloc] init];
    passwordGeneratorViewController.delegate = self;
    
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:passwordGeneratorViewController];
    
    [self presentModalViewController:navigationController animated:YES];

    [navigationController release];
    [passwordGeneratorViewController release];
}

- (void)passwordGeneratorViewController:(PasswordGeneratorViewController *)controller password:(NSString *)password {
    passwordCell.textField.text = password;
}

- (void)openUrlPressed {
    NSString *text = urlCell.textField.text;
    
    NSURL *url = [NSURL URLWithString:text];
    if (url.scheme == nil) {
        url = [NSURL URLWithString:[@"http://" stringByAppendingString:text]];
    }
    
    [[UIApplication sharedApplication] openURL:url];
}

@end
