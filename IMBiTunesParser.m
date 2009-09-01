/*
 iMedia Browser Framework <http://karelia.com/imedia/>
 
 Copyright (c) 2005-2009 by Karelia Software et al.
 
 iMedia Browser is based on code originally developed by Jason Terhorst,
 further developed for Sandvox by Greg Hulands, Dan Wood, and Terrence Talbot.
 The new architecture for version 2.0 was developed by Peter Baumgartner.
 Contributions have also been made by Matt Gough, Martin Wennerberg and others
 as indicated in source files.
 
 The iMedia Browser Framework is licensed under the following terms:
 
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in all or substantial portions of the Software without restriction, including
 without limitation the rights to use, copy, modify, merge, publish,
 distribute, sublicense, and/or sell copies of the Software, and to permit
 persons to whom the Software is furnished to do so, subject to the following
 conditions:
 
	Redistributions of source code must retain the original terms stated here,
	including this list of conditions, the disclaimer noted below, and the
	following copyright notice: Copyright (c) 2005-2009 by Karelia Software et al.
 
	Redistributions in binary form must include, in an end-user-visible manner,
	e.g., About window, Acknowledgments window, or similar, either a) the original
	terms stated here, including this list of conditions, the disclaimer noted
	below, and the aforementioned copyright notice, or b) the aforementioned
	copyright notice and a link to karelia.com/imedia.
 
	Neither the name of Karelia Software, nor Sandvox, nor the names of
	contributors to iMedia Browser may be used to endorse or promote products
	derived from the Software without prior and express written permission from
	Karelia Software or individual contributors, as appropriate.
 
 Disclaimer: THE SOFTWARE IS PROVIDED BY THE COPYRIGHT OWNER AND CONTRIBUTORS
 "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT
 LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE,
 AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
 LIABLE FOR ANY CLAIM, DAMAGES, OR OTHER LIABILITY, WHETHER IN AN ACTION OF
 CONTRACT, TORT, OR OTHERWISE, ARISING FROM, OUT OF, OR IN CONNECTION WITH, THE
 SOFTWARE OR THE USE OF, OR OTHER DEALINGS IN, THE SOFTWARE.
*/


//----------------------------------------------------------------------------------------------------------------------


#pragma mark HEADERS

#import "IMBiTunesParser.h"
#import "IMBParserController.h"
#import "IMBNode.h"
#import "IMBObject.h"
#import "IMBIconCache.h"
#import "NSWorkspace+iMedia.h"
#import "NSFileManager+iMedia.h"
#import <Quartz/Quartz.h>


//----------------------------------------------------------------------------------------------------------------------


#pragma mark 

@interface IMBiTunesParser ()

- (NSString*) identifierWithPersistentID:(NSString*)inPersistentID;
- (BOOL) shoudlUsePlaylist:(NSDictionary*)inPlaylistDict;
- (BOOL) shouldUseTrack:(NSDictionary*)inTrackDict;
- (BOOL) isLeafPlaylist:(NSDictionary*)inPlaylistDict;
- (NSImage*) iconForPlaylist:(NSDictionary*)inPlaylistDict;
- (void) addSubNodesToNode:(IMBNode*)inParentNode playlists:(NSArray*)inPlaylists tracks:(NSDictionary*)inTracks;
- (void) populateNode:(IMBNode*)inNode playlists:(NSArray*)inPlaylists tracks:(NSDictionary*)inTracks;

@end


//----------------------------------------------------------------------------------------------------------------------


#pragma mark 

@implementation IMBiTunesParser

@synthesize appPath = _appPath;
@synthesize plist = _plist;
@synthesize modificationDate = _modificationDate;
@synthesize shouldDisplayLibraryName = _shouldDisplayLibraryName;
@synthesize version = _version;


//----------------------------------------------------------------------------------------------------------------------


// Register this parser, so that it gets automatically loaded...

+ (void) load
{
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
	[IMBParserController registerParserClass:self forMediaType:kIMBMediaTypeAudio];
	[pool release];
}


//----------------------------------------------------------------------------------------------------------------------


// Check if iTunes is installed...

+ (NSString*) iTunesPath
{
	return [[NSWorkspace threadSafeWorkspace] absolutePathForAppBundleWithIdentifier:@"com.apple.iTunes"];
}


+ (BOOL) isInstalled
{
	return [self iTunesPath] != nil;
}


//----------------------------------------------------------------------------------------------------------------------


// Look at the iApps preferences file and find all iPhoto libraries. Create a parser instance for each libary...

+ (NSArray*) parserInstancesForMediaType:(NSString*)inMediaType
{
	NSMutableArray* parserInstances = [NSMutableArray array];

	if ([self isInstalled])
	{
		CFArrayRef recentLibraries = CFPreferencesCopyAppValue((CFStringRef)@"iTunesRecentDatabases",(CFStringRef)@"com.apple.iApps");
		NSArray* libraries = (NSArray*)recentLibraries;
			
		for (NSString* library in libraries)
		{
			NSURL* url = [NSURL URLWithString:library];
			NSString* path = [url path];

			IMBiTunesParser* parser = [[[self class] alloc] initWithMediaType:inMediaType];
			parser.mediaSource = path;
			parser.shouldDisplayLibraryName = libraries.count > 1;
			[parserInstances addObject:parser];
			[parser release];
		}
		
		if (recentLibraries) CFRelease(recentLibraries);
	}
	
	return parserInstances;
}


//----------------------------------------------------------------------------------------------------------------------


- (id) initWithMediaType:(NSString*)inMediaType
{
	if (self = [super initWithMediaType:inMediaType])
	{
		self.appPath = [[self class] iTunesPath];
		self.plist = nil;
		self.modificationDate = nil;
		self.version = 0;
	}
	
	return self;
}


- (void) dealloc
{
	IMBRelease(_appPath);
	IMBRelease(_plist);
	IMBRelease(_modificationDate);
	[super dealloc];
}


//----------------------------------------------------------------------------------------------------------------------


#pragma mark 
#pragma mark Parser Methods


- (IMBNode*) nodeWithOldNode:(const IMBNode*)inOldNode options:(IMBOptions)inOptions error:(NSError**)outError
{
	NSError* error = nil;
	
	// Oops no path, can't create a root node. This is bad...
	
	if (self.mediaSource == nil)
	{
		return nil;
	}
	
	// Create a root node...
	
	IMBNode* node = [[[IMBNode alloc] init] autorelease];
	
	if (inOldNode == nil)
	{
		node.parentNode = nil;
		node.mediaSource = self.mediaSource;
		node.identifier = [self identifierForPath:@"/"];
		node.name = @"iTunes";
		node.icon = [[NSWorkspace threadSafeWorkspace] iconForFile:self.appPath];
		node.groupType = kIMBGroupTypeLibrary;
		node.leaf = NO;
		node.parser = self;
		
		[node.icon setScalesWhenResized:YES];
		[node.icon setSize:NSMakeSize(16.0,16.0)];
	}
	
	// Or an subnode...
	
	else
	{
		node.parentNode = inOldNode.parentNode;
		node.mediaSource = self.mediaSource;
		node.identifier = inOldNode.identifier;
		node.name = inOldNode.name;
		node.icon = inOldNode.icon;
		node.groupType = inOldNode.groupType;
		node.leaf = inOldNode.leaf;
		node.parser = self;
	}
	
	// If we have more than one library then append the library name to the root node...
	
	if (node.isRootNode && self.shouldDisplayLibraryName)
	{
		NSString* path = (NSString*)node.mediaSource;
		NSString* name = [[[path stringByDeletingLastPathComponent] lastPathComponent] stringByDeletingPathExtension];
		node.name = [NSString stringWithFormat:@"%@ (%@)",node.name,name];
	}

	// Watch the XML file. Whenever something in iPhoto changes, we have to replace the WHOLE tree from  
	// the root node down, as we have no way of finding WHAT has changed in iPhoto...
	
	if (node.isRootNode)
	{
		node.watcherType = kIMBWatcherTypeFSEvent;
		node.watchedPath = [(NSString*)node.mediaSource stringByDeletingLastPathComponent];
	}
	else
	{
		node.watcherType = kIMBWatcherTypeNone;
	}
	
	// If the old node was populated, then also populate the new node...
	
	if (inOldNode.isPopulated)
	{
		[self populateNode:node options:inOptions error:&error];
	}
	
	if (outError) *outError = error;
	return node;
}


//----------------------------------------------------------------------------------------------------------------------


// The supplied node is a private copy which may be modified here in the background operation. Parse the 
// iPhoto XML file and create subnodes as needed...

- (BOOL) populateNode:(IMBNode*)inNode options:(IMBOptions)inOptions error:(NSError**)outError
{
	NSError* error = nil;
	
	NSArray* playlists = [self.plist objectForKey:@"Playlists"];
	NSDictionary* tracks = [self.plist objectForKey:@"Tracks"];
	[self addSubNodesToNode:inNode playlists:playlists tracks:tracks]; 
	[self populateNode:inNode playlists:playlists tracks:tracks]; 

	if (outError) *outError = error;
	return error == nil;
}


//----------------------------------------------------------------------------------------------------------------------


// When the parser is deselected, then get rid of the cached plist data. It will be loaded into memory lazily 
// once it is needed again...

- (void) didDeselectParser
{
	self.plist = nil;
}


//----------------------------------------------------------------------------------------------------------------------


#pragma mark 
#pragma mark Helper Methods


// Load the XML file into a plist lazily (on demand). If we notice that an existing cached plist is out-of-date 
// we get rid of it and load it anew...

- (NSDictionary*) plist
{
	NSError* error = nil;
	NSString* path = (NSString*)self.mediaSource;
	NSDictionary* metadata = [[NSFileManager threadSafeManager] attributesOfItemAtPath:path error:&error];
	NSDate* modificationDate = [metadata objectForKey:NSFileModificationDate];
	
	if ([self.modificationDate compare:modificationDate] == NSOrderedAscending)
	{
		self.plist = nil;
	}
	
	if (_plist == nil)
	{
		self.plist = [NSDictionary dictionaryWithContentsOfFile:(NSString*)self.mediaSource];
		self.modificationDate = modificationDate;
		self.version = [[self.plist objectForKey:@"Application Version"] intValue];
	}
	
	return _plist;
}


//----------------------------------------------------------------------------------------------------------------------


// Create an identifier from the AlbumID that is stored in the XML file. An example is "IMBiPhotoParser://AlbumId/17"...

- (NSString*) identifierWithPersistentID:(NSString*)inPersistentID
{
	NSString* path = [NSString stringWithFormat:@"/PlaylistPersistentID/%@",inPersistentID];
	return [self identifierForPath:path];
}


//----------------------------------------------------------------------------------------------------------------------


// Exclude some playlist types...

- (BOOL) shoudlUsePlaylist:(NSDictionary*)inPlaylistDict
{
	if (inPlaylistDict == nil) return NO;
	
	NSNumber* visible = [inPlaylistDict objectForKey:@"Visible"];
	if (visible!=nil && [visible boolValue]==NO) return NO;
	
	if ([[inPlaylistDict objectForKey:@"Distinguished Kind"] intValue]==26) return NO;	// Genius
	
	if ([self.mediaType isEqualToString:kIMBMediaTypeAudio])
	{
		if ([inPlaylistDict objectForKey:@"Movies"]) return NO;
		if ([inPlaylistDict objectForKey:@"TV Shows"]) return NO;
	}
	else if ([self.mediaType isEqualToString:kIMBMediaTypeMovie])
	{
		if ([inPlaylistDict objectForKey:@"Music"]) return NO;
		if ([inPlaylistDict objectForKey:@"Podcasts"]) return NO;
		if ([inPlaylistDict objectForKey:@"Audiobooks"]) return NO;
		if ([inPlaylistDict objectForKey:@"Purchased Music"]) return NO;
		if ([inPlaylistDict objectForKey:@"Party Shuffle"]) return NO;
	}
	
	return YES;
}


//----------------------------------------------------------------------------------------------------------------------


// Everything except folders is a leaf node...

- (BOOL) isLeafPlaylist:(NSDictionary*)inPlaylistDict
{
	return [inPlaylistDict objectForKey:@"Folder"] == nil;
}


//----------------------------------------------------------------------------------------------------------------------


- (NSImage*) iconForPlaylist:(NSDictionary*)inPlaylistDict
{
	NSString* filename = nil;
	
	if (_version < 7)
	{
		if ([inPlaylistDict objectForKey:@"Library"])
			filename = @"itunes-icon-library.png";
		else if ([inPlaylistDict objectForKey:@"Movies"])
			filename =  @"itunes-icon-movies.png";
		else if ([inPlaylistDict objectForKey:@"TV Shows"])
			filename =  @"itunes-icon-tvshows.png";
		else if ([inPlaylistDict objectForKey:@"Podcasts"])
			filename =  @"itunes-icon-podcasts.png";
		else if ([inPlaylistDict objectForKey:@"Audiobooks"])
			filename =  @"itunes-icon-audiobooks.png";
		else if ([inPlaylistDict objectForKey:@"Purchased Music"])
			filename =  @"itunes-icon-purchased.png";
		else if ([inPlaylistDict objectForKey:@"Party Shuffle"])
			filename =  @"itunes-icon-partyshuffle.png";
		else if ([inPlaylistDict objectForKey:@"Folder"])
			filename =  @"itunes-icon-folder.png";
		else if ([inPlaylistDict objectForKey:@"Smart Info"])
			filename =  @"itunes-icon-playlist-smart.png";
		else 
			filename =  @"itunes-icon-playlist-normal.png";
	}
	else
	{
		if ([inPlaylistDict objectForKey:@"master"])
			filename =  @"itunes-icon-music.png";
		else if ([inPlaylistDict objectForKey:@"Library"])
			filename =  @"itunes-icon-music.png";
		else if ([inPlaylistDict objectForKey:@"Music"])
			filename =  @"itunes-icon-music.png";
		else if ([inPlaylistDict objectForKey:@"Movies"])
			filename =  @"itunes-icon-movies.png";
		else if ([inPlaylistDict objectForKey:@"TV Shows"])
			filename =  @"itunes-icon-tvshows.png";
		else if ([inPlaylistDict objectForKey:@"Podcasts"])
			filename =  @"itunes-icon-podcasts7.png";
		else if ([inPlaylistDict objectForKey:@"Audiobooks"])
			filename =  @"itunes-icon-audiobooks.png";
		else if ([inPlaylistDict objectForKey:@"Purchased Music"])
			filename =  @"itunes-icon-purchased7.png";
		else if ([inPlaylistDict objectForKey:@"Party Shuffle"])
			filename =  @"itunes-icon-partyshuffle7.png";
		else if ([inPlaylistDict objectForKey:@"Folder"])
			filename =  @"itunes-icon-folder7.png";
		else if ([inPlaylistDict objectForKey:@"Smart Info"])
			filename =  @"itunes-icon-playlist-smart7.png";
		else 
			filename =  @"itunes-icon-playlist-normal7.png";
	}
	
	if (filename)
	{
		NSBundle* bundle = [NSBundle bundleForClass:[self class]];
		NSString* path = [bundle pathForResource:filename ofType:nil];
		return [[[NSImage alloc] initWithContentsOfFile:path] autorelease];
	}
	
	return nil;
}


//----------------------------------------------------------------------------------------------------------------------


- (void) addSubNodesToNode:(IMBNode*)inParentNode playlists:(NSArray*)inPlaylists tracks:(NSDictionary*)inTracks
{
	// Create the subNodes array on demand - even if turns out to be empty after exiting this method, 
	// because without creating an array we would cause an endless loop...
	
	NSMutableArray* subNodes = (NSMutableArray*) inParentNode.subNodes;
	if (subNodes == nil) inParentNode.subNodes = subNodes = [NSMutableArray array];

	// Now parse the iTunes XML plist and look for albums whose parent matches our parent node. We are 
	// only going to add subnodes that are direct children of inParentNode...
	
	for (NSDictionary* playlistDict in inPlaylists)
	{
		NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
		
		NSString* albumName = [playlistDict objectForKey:@"Name"];
		NSString* parentID = [playlistDict objectForKey:@"Parent Persistent ID"];
		NSString* parentIdentifier = parentID ? [self identifierWithPersistentID:parentID] : [self identifierForPath:@"/"];
		
		if ([self shoudlUsePlaylist:playlistDict] && [inParentNode.identifier isEqualToString:parentIdentifier])
		{
			// Create node for this album...
			
			IMBNode* playlistNode = [[[IMBNode alloc] init] autorelease];
			
			playlistNode.leaf = [self isLeafPlaylist:playlistDict];
			playlistNode.icon = [self iconForPlaylist:playlistDict];
			playlistNode.name = albumName;
			playlistNode.mediaSource = self.mediaSource;
			playlistNode.parser = self;

			// Set the node's identifier. This is needed later to link it to the correct parent node. Please note 
			// that older versions of iPhoto didn't have AlbumId, so we are generating fake AlbumIds in this case
			// for backwards compatibility...
			
			NSString* playlistID = [playlistDict objectForKey:@"Playlist Persistent ID"];
			playlistNode.identifier = [self identifierWithPersistentID:playlistID];

			// Add the new album node to its parent (inRootNode)...
			
			[subNodes addObject:playlistNode];
			playlistNode.parentNode = inParentNode;
		}
		
		[pool release];
	}
}


//----------------------------------------------------------------------------------------------------------------------


- (void) populateNode:(IMBNode*)inNode playlists:(NSArray*)inPlaylists tracks:(NSDictionary*)inTracks
{
	// Create the objects array on demand  - even if turns out to be empty after exiting this method, because
	// without creating an array we would cause an endless loop...
	
	NSMutableArray* objects = (NSMutableArray*) inNode.objects;
	if (objects == nil) inNode.objects = objects = [NSMutableArray array];

	// Look for the correct playlist in the iTunes XML plist. Once we find it, populate the node with IMBVisualObjects
	// for each song in this playlist...
	
	for (NSDictionary* playlistDict in inPlaylists)
	{
		NSAutoreleasePool* pool1 = [[NSAutoreleasePool alloc] init];
		NSString* playlistID = [playlistDict objectForKey:@"Playlist Persistent ID"];
		NSString* playlistIdentifier = [self identifierWithPersistentID:playlistID];

		if ([inNode.identifier isEqualToString:playlistIdentifier])
		{
			NSArray* trackKeys = [playlistDict objectForKey:@"Playlist Items"];

			for (NSDictionary* trackID in trackKeys)
			{
				NSAutoreleasePool* pool2 = [[NSAutoreleasePool alloc] init];
				NSString* key = [[trackID objectForKey:@"Track ID"] stringValue];
				NSDictionary* trackDict = [inTracks objectForKey:key];
			
				if ([self shouldUseTrack:trackDict])
				{
					// Get name and path to file...
					
					NSString* name = [trackDict objectForKey:@"Name"];
					NSString* location = [trackDict objectForKey:@"Location"];
					NSURL* url = [NSURL URLWithString:location];
					NSString* path = [url path];
					BOOL isFileURL = [url isFileURL];
					
					// Create an object...
					
					IMBVisualObject* object = [[IMBVisualObject alloc] init];
					[objects addObject:object];
					[object release];

					// For local files path is preferred (as we gain automatic support for some context menu items)...
					
					if (isFileURL)
					{
						object.name = name;
						object.value = (id)path;
						object.imageRepresentationType = IKImageBrowserPathRepresentationType;
						object.imageRepresentation = path;
					}
					
					// For remote files we'll use a URL (less context menu support)...
					
					else
					{
						object.name = name;
						object.value = (id)url;
						object.imageRepresentationType = IKImageBrowserNSURLRepresentationType;
						object.imageRepresentation = url;
					}
					
					// Add metadata and convert the duration property to seconds. Also note that the original
					// key "Total Time" is not bindings compatible as it contains a space...
					
					NSMutableDictionary* metadata = [NSMutableDictionary dictionaryWithDictionary:trackDict];
					object.metadata = metadata;

					double duration = [[trackDict objectForKey:@"Total Time"] doubleValue] / 1000.0;
					[metadata setObject:[NSNumber numberWithDouble:duration] forKey:@"duration"]; 
					
					NSString* artist = [trackDict objectForKey:@"Artist"];
					if (artist) [metadata setObject:artist forKey:@"artist"]; 
					
					NSString* album = [trackDict objectForKey:@"Album"];
					if (album) [metadata setObject:album forKey:@"album"]; 
				}
				
				[pool2 release];
			}
		}
		
		[pool1 release];
	}
}


//----------------------------------------------------------------------------------------------------------------------


// A track is eligible if it has a name, a url, and if it is not a movie file...

- (BOOL) shouldUseTrack:(NSDictionary*)inTrackDict
{
	if (inTrackDict == nil) return NO;
	if ([inTrackDict objectForKey:@"Name"] == nil) return NO;
	if ([[inTrackDict objectForKey:@"Location"] length] == 0) return NO;
	if ([[inTrackDict objectForKey:@"Has Video"] boolValue] == 1) return NO;
	
	return YES;
}

//----------------------------------------------------------------------------------------------------------------------


@end