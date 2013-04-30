//
//  GBInfiniteListView.h
//  GBInfiniteList
//
//  Created by Luka Mirosevic on 30/04/2013.
//  Copyright (c) 2013 Goonbee. All rights reserved.
//

#import <UIKit/UIKit.h>

//structure:
//main header which imports all the other classes
//view
//which has a delegate and dataSource protocols
//it has a scrollview subview which is same size when init is called, but sticks to the center
//you start it up using initWithFrame...maybe initWithCode

//maybe a premade viewController subclass comes with it which has a bunch of these already preimplemented and the view set as its property and it's delegate and datasource pointing to it?

//properties (just the readonly ones)

//datasource (as soon as it's set, it triggers the loading)
//these are called after init, or after reset... only once... you can get them from readonly properties
//outer padding
//vertical item margin (collapsible)
//column count
//column horizontal margin (collapsible)

//isItemAvailable, passes in item id, and calls before requesting each item
//if you return YES, he asks for next item
//if yuo return NO, he sends a "no more items" message to delegate
//ask for next item, passes in ID and itself which gives datasource access to reusable pool
//are there more items? it calls this before showing the loading thing, if it gets a yes, it shows the loading and asks for more items
//should show loading aka can you load more? say yes if there is more on the server, otherwise no. which signifies the end of the list
//load more... sent if you answer YES to "should show loading"?
//header view (height is retained, width is stretched)
//empty view (height is retained, width is stretched)
//recycledView:(UIVIew) usedByItem:(NSUINT)... here i wud cancel the async update of the view (cuz its used by someone else now)... but still cache the result locally

//delegate (set this first)
//itemPressed, passes along subview
//scrolled to bottom
//scrolledToPosition, passes in new visible scroll region
//scrolledToItems, passes in first and last visible items
//no more items... sent when you answer NO to "can you load more?"
//item went offscreen...
//item came on screen...
//started loading... sent when you answer YES to "can you load more?"
//finished loading... sent when you send it the "more items available" message

//methods
//more items available, hides the laoding thing and requests the next few items.
//scroll to top
//scroll to: pass in a location to which the top edge should scroll (this is thresholded)
//show loading indicator at the bottom
//redraw visible items
//reload
//reset (removes everything, cleans up memory and scrolls to top with no animation)
//is item on screen?

//internals
//has pools of reusable views which can be changed completely except for width
//has an array of view sizes so it knows which view to draw when, especially when scrolling up




@interface GBInfiniteListView : UIView

@end
