{
    fpGFX  -  Free Pascal Graphics Library
    Copyright (C) 2000 - 2001 by
      Areca Systems GmbH / Sebastian Guenther, sg@freepascal.org

    X11/XLib target implementation

    See the file COPYING.modifiedLGPL, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
}


unit GFX_X11;

{$IFDEF Debug}
  {$ASSERTIONS On}
{$ENDIF}

{$mode objfpc}{$H+}

{ Disable this, if you do not want Xft to be used for drawing text }
{.$Define XftSupport}

interface

uses
  SysUtils, Classes,   // FPC units
  X, XLib, XUtil,     // X11 units
  {$IFDEF XftSupport}
  unitxft;            // Xft font support
  {$ENDIF}
  GfxBase,            // fpGFX units
  GELDirty;           // fpGFX emulation layer


resourcestring
  // X11 exception strings
  SGCCreationFailed = 'Creation of X11 graphics context failed';
  SXCanvasInvalidFontClass = 'Tried to set font of class "%s" into X11 context; only TXFont is allowed.';
  SOpenDisplayFailed = 'Opening of display "%s" failed';
  SWindowCreationFailed = 'Creation of X11 window failed';
  SWindowUnsupportedPixelFormat = 'Window uses unsupported pixel format: %d bits per pixel';
  SNoDefaultFont = 'Unable to load default font';
  SIncompatibleCanvasForBlitting = 'Cannot blit from %s to %s';


type
  EX11Error = class(EGfxError);
  TX11Canvas  = class;
  TX11Application = class;
  
  // Returns True if it 'ate' the event
  TX11EventFilter = function (const AEvent: TXEvent): Boolean of object;

  { TX11Font }

  TX11Font = class(TFCustomFont)
  private
    FFontStruct: PXFontStruct;
  public
    constructor Create(const Descriptor: String);
    destructor  Destroy; override;
    class function GetDefaultFontName(const AFontClass: TGfxFontClass): String; override;
    property    FontStruct: PXFontStruct read FFontStruct;
  end;


  PX11CanvasState = ^TX11CanvasState;
  TX11CanvasState = record
    Prev: PX11CanvasState;
    Matrix: TGfxMatrix;
    Region: TRegion;
    Color: TGfxPixel;
    Font: TFCustomFont;
  end;


  { TX11Canvas }

  TX11Canvas = class(TFCustomCanvas)
  private
    FHandle: X.TDrawable;
    FGC: TGC;
    FVisual: PVisual;
    FRegion: TRegion;
    FDefaultFont: PXFontStruct;
    FFontStruct: PXFontStruct;
    FStateStackpointer: PX11CanvasState;
    FColormap: TColormap;
    FCurColor: TGfxPixel;
    FFont: TFCustomFont;
    {$IFDEF XftSupport}
    FXftDraw: PXftDraw;
    {$ENDIF}
    procedure   Resized(NewWidth, NewHeight: Integer);
  protected
    function    DoExcludeClipRect(const ARect: TRect): Boolean; override;
    function    DoIntersectClipRect(const ARect: TRect): Boolean; override;
    function    DoUnionClipRect(const ARect: TRect): Boolean; override;
    function    DoGetClipRect: TRect; override;
    procedure   DoDrawArc(const ARect: TRect; StartAngle, EndAngle: Single); override;
    procedure   DoDrawCircle(const ARect: TRect); override;
    procedure   DoDrawLine(const AFrom, ATo: TPoint); override;
    procedure   DoDrawRect(const ARect: TRect); override;
    procedure   DoDrawPoint(const APoint: TPoint); override;
    procedure   DoFillRect(const ARect: TRect); override;
    procedure   DoTextOut(const APosition: TPoint; const AText: String); override;
    procedure   DoCopyRect(ASource: TFCustomCanvas; const ASourceRect: TRect; const ADestPos: TPoint); override;
    procedure   DoMaskedCopyRect(ASource, AMask: TFCustomCanvas; const ASourceRect: TRect; const AMaskPos, ADestPos: TPoint); override;
    procedure   DoDrawImageRect(AImage: TFCustomBitmap; ASourceRect: TRect; const ADestPos: TPoint); override;
  public
    constructor Create(AColormap: TColormap; AXDrawable: X.TDrawable; ADefaultFont: PXFontStruct);
    destructor  Destroy; override;
    function    MapColor(const AColor: TGfxColor): TGfxPixel; override;
    function    FontCellHeight: Integer; override;
    function    TextExtent(const AText: String): TSize; override;
    procedure   SaveState; override;
    procedure   RestoreState; override;
    procedure   EmptyClipRect; override;
    procedure   SetColor_(AColor: TGfxPixel); override;
    procedure   SetFont(AFont: TFCustomFont); override;
    procedure   SetLineStyle(ALineStyle: TGfxLineStyle); override;
    procedure   DrawPolyLine(const Coords: array of TPoint); override;
    property    Handle: X.TDrawable read FHandle;
    property    GC: TGC read FGC;
    property    Visual: PVisual read FVisual;
    property    Colormap: TColormap read FColormap;
    property    Region: TRegion read FRegion;
  end;


  TX11WindowCanvas = class(TX11Canvas)
  public
    constructor Create(AColormap: TColormap;
      AXDrawable: X.TDrawable; ADefaultFont: PXFontStruct);
  end;


  TX11PixmapCanvas = class(TX11Canvas)
  public
    constructor Create(AColormap: TColormap;
      AHandle: TPixmap; APixelFormat: TGfxPixelFormat);
    destructor Destroy; override;
  end;


  TX11MonoPixmapCanvas = class(TX11PixmapCanvas)
    constructor Create(AColormap: TColormap; AHandle: TPixmap);
  end;

  { TX11Bitmap }

  TX11Bitmap = class(TFCustomBitmap)
  private
    IsLocked: Boolean;
  public
    constructor Create(AWidth, AHeight: Integer; APixelFormat: TGfxPixelFormat); override;
    destructor  Destroy; override;
    procedure   Lock(var AData: Pointer; var AStride: LongWord); override;
    procedure   Unlock; override;
  end;

  { TX11Screen }

  TX11Screen = class(TFCustomScreen)
  private
    FScreenIndex: Integer;
    FScreenInfo: PScreen;
  public
    constructor Create; override;
    property    ScreenIndex: Integer read FScreenIndex;
    property    ScreenInfo: PScreen read FScreenInfo;
  end;


  { TX11Application }

  TX11Application = class(TFCustomApplication)
  private
    DoBreakRun: Boolean;
    FDirtyList: TDirtyList;
    FDisplayName: String;
    FDefaultFont: PXFontStruct;
    FEventFilter: TX11EventFilter;
    Handle: PDisplay;
    FWMProtocols: TAtom;		  // Atom for "WM_PROTOCOLS"
    FWMDeleteWindow: TAtom;		// Atom for "WM_DELETE_WINDOW"
    FWMHints: TAtom;			    // Atom for "_MOTIF_WM_HINTS"
    property    DirtyList: TDirtyList read FDirtyList;
    function    FindWindowByXID(XWindowID: X.TWindow): TFCustomWindow;
  public
    { default methods }
    constructor Create; override;
    destructor  Destroy; override;
    procedure   AddWindow(AWindow: TFCustomWindow); override;
    procedure   Initialize(ADisplayName: String = ''); override;
    procedure   Run; override;
    procedure   Quit; override;
    { properties }
    property    DisplayName: String read FDisplayName write FDisplayName;
    property    EventFilter: TX11EventFilter read FEventFilter write FEventFilter;
  end;

  { TX11Window }

  TX11Window = class(TFCustomWindow)
  private
    FParent: TFCustomWindow;
    FComposeStatus: TXComposeStatus;
    FComposeBuffer: String[32];
    FCurCursorHandle: X.TCursor;
    function    StartComposing(const Event: TXKeyEvent): TKeySym;
    procedure   EndComposing;
    procedure   KeyPressed(var Event: TXKeyPressedEvent); message X.KeyPress;
    procedure   KeyReleased(var Event: TXKeyReleasedEvent); message X.KeyRelease;
    procedure   ButtonPressed(var Event: TXButtonPressedEvent); message X.ButtonPress;
    procedure   ButtonReleased(var Event: TXButtonReleasedEvent); message X.ButtonRelease;
    procedure   EnterWindow(var Event :TXEnterWindowEvent); message X.EnterNotify;
    procedure   LeaveWindow(var Event :TXLeaveWindowEvent); message X.LeaveNotify;
    procedure   PointerMoved(var Event: TXPointerMovedEvent); message X.MotionNotify;
    procedure   Expose(var Event: TXExposeEvent); message X.Expose;
    procedure   FocusIn(var Event: TXFocusInEvent); message X.FocusIn;
    procedure   FocusOut(var Event: TXFocusOutEvent); message X.FocusOut;
    procedure   Map(var Event: TXMapEvent); message X.MapNotify;
    procedure   Unmap(var Event: TXUnmapEvent); message X.UnmapNotify;
    procedure   Reparent(var Event: TXReparentEvent); message X.ReparentNotify;
    procedure   Configure(var Event: TXConfigureEvent); message X.ConfigureNotify;
    procedure   ClientMessage(var Event: TXClientMessageEvent); message X.ClientMessage;
  protected
    IsExposing: Boolean;
    CanMaximize: Boolean;
    function    GetTitle: String; override;
    function    ConvertShiftState(AState: Cardinal): TShiftState;
    function    KeySymToKeycode(KeySym: TKeySym): Word;
    procedure   SetTitle(const ATitle: String); override;
    procedure   DoSetCursor; override;
    procedure   UpdateMotifWMHints;
  public
    constructor Create(AParent: TFCustomWindow; AWindowOptions: TGfxWindowOptions); override;
    destructor  Destroy; override;
    procedure   DefaultHandler(var Message); override;
    procedure   SetPosition(const APosition: TPoint); override;
    procedure   SetSize(const ASize: TSize); override;
    procedure   SetMinMaxSize(const AMinSize, AMaxSize: TSize); override;
    procedure   SetClientSize(const ASize: TSize); override;
    procedure   SetMinMaxClientSize(const AMinSize, AMaxSize: TSize); override;
    procedure   Show; override;
    procedure   Invalidate(const ARect: TRect); override;
    procedure   PaintInvalidRegion; override;
    procedure   CaptureMouse; override;
    procedure   ReleaseMouse; override;
  end;


var
  LeaderWindow: X.TWindow;
  ClientLeaderAtom: TAtom;

function RectToXRect(const ARect: TRect): TXRectangle;
function XRectToRect(const ARect: TXRectangle): TRect;
function GetXEventName(Event: LongInt): String;


implementation

uses
  GELImage, fpgfx;

resourcestring
  SFontCreationFailed = 'Could not create font with descriptor "%s"';

{ TX11Font }

constructor TX11Font.Create(const Descriptor: String);
begin
  inherited Create;

  FFontStruct := XLoadQueryFont(GFApplication.Handle, PChar(Descriptor));
  if not Assigned(FFontStruct) then
    raise EX11Error.CreateFmt(SFontCreationFailed, [Descriptor]);
end;

destructor TX11Font.Destroy;
begin
  if Assigned(FontStruct) then
  begin
    if FontStruct^.fid <> 0 then
      XUnloadFont(GFApplication.Handle, FontStruct^.fid);
    XFreeFontInfo(nil, FontStruct, 0);
  end;
  inherited Destroy;
end;

class function TX11Font.GetDefaultFontName(const AFontClass: TGfxFontClass): String;
const
  FontNames: array[TGfxFontClass] of String = (
    'times', 'bitstream vera sans', 'courier', 'symbol');
begin
  Result := FontNames[AFontClass];
end;


{ TX11Canvas }

constructor TX11Canvas.Create(AColormap: TColormap; AXDrawable: X.TDrawable; ADefaultFont: PXFontStruct);
var
  DummyWnd: PWindow;
  DummyInt: LongInt;
  GCValues: XLib.TXGCValues;
begin
  inherited Create;
  FColormap         := AColormap;
  FHandle           := AXDrawable;
  FDefaultFont      := ADefaultFont;
  XGetGeometry(GFApplication.Handle, Handle, @DummyWnd, @DummyInt, @DummyInt,
    @FWidth, @FHeight, @DummyInt, @DummyInt);

  GCValues.graphics_exposures := False;
  FGC := XCreateGC(GFApplication.Handle, Handle, GCGraphicsExposures, @GCValues);
  if not Assigned(GC) then
    raise EX11Error.Create(SGCCreationFailed);

  XSetLineAttributes(GFApplication.Handle, GC, 0,
    LineSolid, CapNotLast, JoinMiter);

  FFontStruct := FDefaultFont;
  if Assigned(FFontStruct) then
    XSetFont(GFApplication.Handle, GC, FFontStruct^.FID);

  FRegion := XCreateRegion;
  Resized(Width, Height);	// Set up a proper clipping region

  {$IFDEF XftSupport}
    {$IFDEF BUFFERING}
    FBufferWin := XdbeAllocateBackBufferName(gApplication, FWin, nil);
    if FBufferWin > 0 then
      FXftDrawBuffer := XftDrawCreate(gApplication.Handle, FBufferWin,
        XDefaultVisual(gApplication.Handle, GfxDefaultScreen),
        XDefaultColormap(gApplication.Handle, GfxDefaultScreen));
    {$ELSE}
    //  FBufferWin := -1;
    //  FXftDrawBuffer := nil;
    {$ENDIF}
    FXftDraw := XftDrawCreate(gApplication.Handle, Handle,
      XDefaultVisual(gApplication.Handle, XDefaultScreen(gApplication.Handle)),
      XDefaultColormap(gApplication.Handle, XDefaultScreen(gApplication.Handle)));
  {$ENDIF XftSupport}
end;

destructor TX11Canvas.Destroy;
begin
  {$IFDEF XftSupport}
  if FXftDraw <> nil then
    XftDrawDestroy(FXftDraw);
  {$ENDIF}
  XDestroyRegion(Region);
  if Assigned(GC) then
    XFreeGC(GFApplication.Handle, GC);
  inherited Destroy;
end;

procedure TX11Canvas.SaveState;
var
  SavedState: PX11CanvasState;
  NewRegion: TRegion;
begin
  New(SavedState);
  SavedState^.Prev := FStateStackpointer;
  SavedState^.Matrix := Matrix;
  SavedState^.Region := Region;
  NewRegion := XCreateRegion;
  XUnionRegion(Region, NewRegion, NewRegion);
  FRegion := NewRegion;
  SavedState^.Color := FCurColor;
  SavedState^.Font := FFont;
  FStateStackpointer := SavedState;
end;

procedure TX11Canvas.RestoreState;
var
  SavedState: PX11CanvasState;
begin
  SavedState := FStateStackpointer;
  FStateStackpointer := SavedState^.Prev;
  Matrix := SavedState^.Matrix;

  XDestroyRegion(Region);
  FRegion := SavedState^.Region;
  XSetRegion(GFApplication.Handle, GC, Region);

  SetColor_(SavedState^.Color);
  SetFont(SavedState^.Font);

  Dispose(SavedState);
end;

procedure TX11Canvas.EmptyClipRect;
begin
  XDestroyRegion(Region);
  FRegion := XCreateRegion;
  XSetRegion(GFApplication.Handle, GC, Region);
end;

function TX11Canvas.DoExcludeClipRect(const ARect: TRect): Boolean;
var
  RectRegion: TRegion;
  XRect: TXRectangle;
begin
  XRect := RectToXRect(ARect);
  RectRegion := XCreateRegion;
  XUnionRectWithRegion(@XRect, RectRegion, RectRegion);
  XSubtractRegion(Region, RectRegion, Region);
  XDestroyRegion(RectRegion);
  XSetRegion(GFApplication.Handle, GC, Region);
  Result := XEmptyRegion(Region) = 0;
end;

function TX11Canvas.DoIntersectClipRect(const ARect: TRect): Boolean;
var
  RectRegion: TRegion;
  XRect: TXRectangle;
begin
  XRect := RectToXRect(ARect);
  RectRegion := XCreateRegion;
  XUnionRectWithRegion(@XRect, RectRegion, RectRegion);
  XIntersectRegion(Region, RectRegion, Region);
  XDestroyRegion(RectRegion);
  XSetRegion(GFApplication.Handle, GC, Region);
  Result := XEmptyRegion(Region) = 0;
end;

function TX11Canvas.DoUnionClipRect(const ARect: TRect): Boolean;
var
  XRect: TXRectangle;
begin
  XRect := RectToXRect(ARect);
  XUnionRectWithRegion(@XRect, Region, Region);
  XSetRegion(GFApplication.Handle, GC, Region);
  Result := XEmptyRegion(Region) = 0;
end;

function TX11Canvas.DoGetClipRect: TRect;
var
  XRect: TXRectangle;
begin
  XClipBox(Region, @XRect);
  Result := XRectToRect(XRect);
end;

function TX11Canvas.MapColor(const AColor: TGfxColor): TGfxPixel;
var
  Color: TXColor;
begin
  Color.Pixel := 0;
  Color.Red := AColor.Red;
  Color.Green := AColor.Green;
  Color.Blue := AColor.Blue;
  XAllocColor(GFApplication.Handle, Colormap, @Color);
  Result := Color.Pixel;
end;

procedure TX11Canvas.SetColor_(AColor: TGfxPixel);
begin
  if AColor <> FCurColor then
  begin
    XSetForeground(GFApplication.Handle, GC, AColor);
    FCurColor := AColor;
  end;
end;

procedure TX11Canvas.SetFont(AFont: TFCustomFont);
begin
  if AFont = FFont then
    exit;

  FFont := AFont;

  if not Assigned(AFont) then
  begin
    if FFontStruct = FDefaultFont then
      exit;
    FFontStruct := FDefaultFont;
  end else
  begin
    if not AFont.InheritsFrom(TX11Font) then
      raise EGfxError.CreateFmt(SXCanvasInvalidFontClass, [AFont.ClassName]);
    if TX11Font(AFont).FontStruct = FFontStruct then
      exit;
    FFontStruct := TX11Font(AFont).FontStruct;
  end;
  XSetFont(GFApplication.Handle, GC, FFontStruct^.FID);
end;

procedure TX11Canvas.SetLineStyle(ALineStyle: TGfxLineStyle);
const
  DotDashes: array[0..1] of Char = #4#2;
  { It was #1#1 which gives 1 pixel dots. Now it gives a 4 pixel line and a
    2 pixel space. }
begin
  case ALineStyle of
    lsSolid:
      XSetLineAttributes(GFApplication.Handle, GC, 0,
        LineSolid, CapNotLast, JoinMiter);
    lsDot:
      begin
        XSetLineAttributes(GFApplication.Handle, GC, 0,
          LineOnOffDash, CapNotLast, JoinMiter);
        XSetDashes(GFApplication.Handle, GC, 0, DotDashes, 2);
      end;
  end;
end;


procedure TX11Canvas.DoDrawArc(const ARect: TRect; StartAngle, EndAngle: Single);
begin
  with ARect do
    XDrawArc(GFApplication.Handle, Handle, GC,
      Left, Top, Right - Left - 1, Bottom - Top - 1,
      Round(StartAngle * 64), Round((EndAngle - StartAngle) * 64));
end;


procedure TX11Canvas.DoDrawCircle(const ARect: TRect);
begin
  with ARect do
    XDrawArc(GFApplication.Handle, Handle, GC,
      Left, Top, Right - Left - 1, Bottom - Top - 1, 0, 23040);
end;


procedure TX11Canvas.DoDrawLine(const AFrom, ATo: TPoint);
begin
  XDrawLine(GFApplication.Handle, Handle, GC, AFrom.x, AFrom.y, ATo.x, ATo.y);
end;


procedure TX11Canvas.DrawPolyLine(const Coords: array of TPoint);
var
  Points: PXPoint;
  CoordsIndex, PointsIndex: Integer;
  Pt: TPoint;
begin
  Points := nil;
  GetMem(Points, (High(Coords) - Low(Coords) + 1) * SizeOf(TXPoint));
  CoordsIndex := Low(Coords);
  PointsIndex := 0;
  for CoordsIndex := Low(Coords) to High(Coords) do
  begin
    Pt := Transform(Coords[CoordsIndex]);
    Points[PointsIndex].x := Pt.x;
    Points[PointsIndex].y := Pt.y;
    Inc(PointsIndex);
  end;

  XDrawLines(GFApplication.Handle, Handle, GC, Points, PointsIndex, CoordModeOrigin);

  FreeMem(Points);
end;


procedure TX11Canvas.DoDrawRect(const ARect: TRect);
begin
  with ARect do
    XDrawRectangle(GFApplication.Handle, Handle, GC, Left, Top,
      Right - Left - 1, Bottom - Top - 1);
end;


procedure TX11Canvas.DoDrawPoint(const APoint: TPoint);
begin
  XDrawPoint(GFApplication.Handle, Handle, GC, APoint.x, APoint.y);
end;


procedure TX11Canvas.DoFillRect(const ARect: TRect);
begin
  with ARect do
    XFillRectangle(GFApplication.Handle, Handle, GC, Left, Top,
      Right - Left, Bottom - Top);
end;


function TX11Canvas.FontCellHeight: Integer;
begin
  {$note XftSupport needs to be handled here!!! }
  Result := FFontStruct^.Ascent + FFontStruct^.Descent;
end;


function TX11Canvas.TextExtent(const AText: String): TSize;
var
  Direction, FontAscent, FontDescent: LongInt;
  CharStruct: TXCharStruct;
begin
//  inherited;
  if Length(AText) = 0 then
  begin
    Result.cx := 0;
    Result.cy := 0;
  end else
  begin
    XQueryTextExtents(GFApplication.Handle, XGContextFromGC(GC),
      PChar(AText), Length(AText),
      @Direction, @FontAscent, @FontDescent, @CharStruct);
    Result.cx := CharStruct.Width;
    Result.cy := CharStruct.Ascent + CharStruct.Descent;
  end;
end;


procedure TX11Canvas.DoTextOut(const APosition: TPoint; const AText: String);
var
  WideText: PWideChar;
  AnsiText: string;
  Size: Integer;
  {$IFDEF XftSupport}
  fnt: PXftFont;
  fntColor: TXftColor;
  s: String16;

    procedure SetXftColor(c: TGfxPixel; var colxft: TXftColor);
    begin
      colxft.color.blue  := (c and $000000FF) shl 8;
      colxft.color.green := (c and $0000FF00);
      colxft.color.red   := (c and $00FF0000) shr 8;

      colxft.color.alpha := (c and $7F000000) shr 15;
      colxft.color.alpha := colxft.color.alpha xor $FFFF;  // invert: 0 in GfxColor means not translucent

      colxft.pixel := 0;
    end;

  {$ENDIF}
begin
  if Length(AText) < 1 then
    Exit; //==>
    
  {$IFDEF XftSupport}
  fnt := XftFontOpenName(gApplication.Handle, XDefaultScreen(gApplication.Handle), PChar('Sans-12'));
  SetXftColor(FCurColor,fntColor);
  s := u8(AText);
//  XftDrawString8(FXftDraw, fntColor, fnt, APosition.x, Aposition.y, PChar(AText),Length(AText));
  XftDrawString16(FXftDraw, fntColor, fnt, APosition.x, Aposition.y * 3, @s[1], Length16(s));
  XftFontClose(gApplication.Handle, fnt);
  {$ELSE}
  XDrawString(GFApplication.Handle, Handle, GC, APosition.x,
    APosition.y + FFontStruct^.ascent, PChar(AText), Length(AText));

{   Size := Utf8ToUnicode(nil, PChar(AText), 0);
    WideText := GetMem(Size * 2);
    Utf8ToUnicode(WideText, PChar(AText), Size);

  XwcDrawText(gApplication.Handle, Handle, GC, APosition.x,
    APosition.y + FFontStruct^.ascent, PXwcTextItem(WideText), Length(WideText));

    FreeMem(WideText);
}
  {$ENDIF}
end;


procedure TX11Canvas.DoCopyRect(ASource: TFCustomCanvas; const ASourceRect: TRect;
  const ADestPos: TPoint);
var
  DestPos: TPoint;
  RealHeight: Integer;
begin
  if not ASource.InheritsFrom(TX11Canvas) then
    raise EX11Error.CreateFmt(SIncompatibleCanvasForBlitting,
      [ASource.ClassName, Self.ClassName]);

  if (ASource <> Self) and (ASource.PixelFormat.FormatType = ftMono) then
  begin
    // !!!: This case will probably be removed completely very soon
    RealHeight := ASourceRect.Bottom - ASourceRect.Top;
    if DestPos.y + RealHeight > Height then
      RealHeight := Height - ADestPos.y;
    XSetClipMask(GFApplication.Handle, GC, TX11Canvas(ASource).Handle);
    XSetClipOrigin(GFApplication.Handle, GC, ADestPos.x, ADestPos.y);
    XFillRectangle(GFApplication.Handle, Handle, GC, ADestPos.x, ADestPos.y,
      ASource.Width, RealHeight);
    // Restore old clipping settings
    XSetClipOrigin(GFApplication.Handle, GC, 0, 0);
    XSetRegion(GFApplication.Handle, GC, Region);
  end else
    XCopyArea(GFApplication.Handle, TX11Canvas(ASource).Handle, Handle, GC,
      ASourceRect.Left, ASourceRect.Top,
      ASourceRect.Right - ASourceRect.Left,
      ASourceRect.Bottom - ASourceRect.Top, ADestPos.x, ADestPos.y);
end;


procedure TX11Canvas.DoMaskedCopyRect(ASource, AMask: TFCustomCanvas;
  const ASourceRect: TRect; const AMaskPos, ADestPos: TPoint);
var
  RectWidth, RectHeight: Integer;
  DestPos, MaskPos: TPoint;
  SourceRect: TRect;
begin
  if not ASource.InheritsFrom(TX11Canvas) then
    raise EX11Error.CreateFmt(SIncompatibleCanvasForBlitting,
      [ASource.ClassName, Self.ClassName]);
  if not AMask.InheritsFrom(TX11MonoPixmapCanvas) then
    raise EX11Error.CreateFmt(SIncompatibleCanvasForBlitting,
      [AMask.ClassName, Self.ClassName]);

  RectWidth := ASourceRect.Right - ASourceRect.Left;
  RectHeight := ASourceRect.Bottom - ASourceRect.Top;

  { !!!: Attention! The current implementation only clips to the ClipRect,
    i.e. the outer bounds of the current clipping region. In other words, the
    result is only correct for a simple rectangle clipping region. }
  with DoGetClipRect do
  begin
    if (ADestPos.x + RectWidth <= Left) or (ADestPos.y + RectHeight <= Top) then
      exit;

    DestPos := ADestPos;
    MaskPos := AMaskPos;
    SourceRect := ASourceRect;

    if DestPos.x < Left then
    begin
      Inc(MaskPos.x, Left - DestPos.x);
      Inc(SourceRect.Left, Left - DestPos.x);
      DestPos.x := Left;
    end;
    if DestPos.y < Top then
    begin
      Inc(MaskPos.y, Top - DestPos.y);
      Inc(SourceRect.Top, Top - DestPos.y);
      DestPos.y := Top;
    end;

    if (DestPos.x >= Right) or (DestPos.y >= Bottom) then
      exit;

    if DestPos.x + RectWidth > Right then
      RectWidth := Right - DestPos.x;
    if DestPos.y + RectHeight > Bottom then
      RectHeight := Bottom - DestPos.y;
  end;

  if (RectWidth <= 0) or (RectHeight <= 0) then
    exit;


  XSetClipMask(GFApplication.Handle, GC, TX11Canvas(AMask).Handle);
  XSetClipOrigin(GFApplication.Handle, GC,
    DestPos.x - MaskPos.x, DestPos.y - MaskPos.y);

  XCopyArea(GFApplication.Handle, TX11Canvas(ASource).Handle, Handle, GC,
    SourceRect.Left, SourceRect.Top, RectWidth, RectHeight,
    DestPos.x, DestPos.y);

  // Restore old clipping settings
  XSetClipOrigin(GFApplication.Handle, GC, 0, 0);
  XSetRegion(GFApplication.Handle, GC, Region);
end;

procedure TX11Canvas.DoDrawImageRect(AImage: TFCustomBitmap; ASourceRect: TRect;
  const ADestPos: TPoint);
var
  Image: XLib.PXImage;
  ConvertFormat: TGfxPixelFormat;
begin
  ASSERT(AImage.InheritsFrom(TX11Bitmap));
  {$IFDEF Debug}
  ASSERT(not TXImage(AImage).IsLocked);
  {$ENDIF}

  // !!!: Add support for XF86 4 and XShm etc. to speed this up!
  Image := XCreateImage(GFApplication.Handle, Visual,
    FormatTypeBPPTable[PixelFormat.FormatType], ZPixmap, 0, nil,
    ASourceRect.Right - ASourceRect.Left,
    ASourceRect.Bottom - ASourceRect.Top, 8, 0);

  { Here its necessary to alloc an extra byte, otherwise it will fail on 32-bits
   machines, but still work on 64-bits machines. The cause of this is unknown. }
  Image^.data := GetMem(Image^.bytes_per_line * (ASourceRect.Bottom - ASourceRect.Top) + 1);

  if (AImage.PixelFormat.FormatType = ftMono) and
    Self.InheritsFrom(TX11MonoPixmapCanvas) then
    // mirror the bits within all image data bytes...:
    FlipMonoImageBits(ASourceRect, TX11Bitmap(AImage).Data,
      TX11Bitmap(AImage).Stride, 0, 0, Image^.data, Image^.bytes_per_line)
  else
  begin
    ConvertFormat := PixelFormat;
    ConvertImage(ASourceRect, AImage.PixelFormat, AImage.Palette,
      TX11Bitmap(AImage).Data, TX11Bitmap(AImage).Stride,
      0, 0, ConvertFormat, Image^.data, Image^.bytes_per_line);
  end;

  XPutImage(GFApplication.Handle, Handle, GC,
    Image, 0, 0, ADestPos.x, ADestPos.y, AImage.Width, AImage.Height);
    
  FreeMem(Image^.data);
  Image^.data := nil;
  XDestroyImage(Image);
end;


procedure TX11Canvas.Resized(NewWidth, NewHeight: Integer);
var
  XRect: TXRectangle;
begin
  FWidth := NewWidth;
  FHeight := NewHeight;

  XDestroyRegion(Region);
  XRect.x := 0;
  XRect.y := 0;
  XRect.Width := Width;
  XRect.Height := Height;
  FRegion := XCreateRegion;
  XUnionRectWithRegion(@XRect, Region, Region);
end;


{ TX11WindowCanvas }

constructor TX11WindowCanvas.Create(AColormap: TColormap;
  AXDrawable: X.TDrawable; ADefaultFont: PXFontStruct);
var
  Attr: XLib.TXWindowAttributes;
begin
  inherited Create(AColormap, AXDrawable, ADefaultFont);

  XGetWindowAttributes(GFApplication.Handle, Handle, @Attr);
  FVisual := Attr.Visual;

  case Attr.Depth of
    1: PixelFormat.FormatType := ftMono;
//    4: PixelFormat.FormatType := ftPal4;
    4,
    8: PixelFormat.FormatType := ftPal8;
    16: PixelFormat.FormatType := ftRGB16;
//    24: PixelFormat.FormatType := ftRGB24;
    24,
    32: PixelFormat.FormatType := ftRGB32;
    else
      raise EX11Error.CreateFmt(SWindowUnsupportedPixelFormat, [Attr.Depth]);
  end;

  if Attr.Depth >= 16 then
  begin
    PixelFormat.RedMask := Visual^.red_mask;
    PixelFormat.GreenMask := Visual^.green_mask;
    PixelFormat.BlueMask := Visual^.blue_mask;
  end;
end;


{ TX11PixmapCanvas }

constructor TX11PixmapCanvas.Create(AColormap: TColormap;
  AHandle: TPixmap; APixelFormat: TGfxPixelFormat);
begin
  inherited Create(AColormap, AHandle, nil);
  FPixelFormat := APixelFormat;
end;


destructor TX11PixmapCanvas.Destroy;
begin
  XFreePixmap(GFApplication.Handle, Handle);
  inherited Destroy;
end;

{ TX11MonoPixmapCanvas }

constructor TX11MonoPixmapCanvas.Create(AColormap: TColormap; AHandle: TPixmap);
begin
  inherited Create(AColormap, AHandle, PixelFormatMono);
end;

{ TX11Bitmap }

constructor TX11Bitmap.Create(AWidth, AHeight: Integer; APixelFormat: TGfxPixelFormat);
begin
  inherited Create(AWidth, AHeight, APixelFormat);

  case APixelFormat.FormatType of
    ftMono:
      FStride := (AWidth + 7) shr 3;
    else
      FStride := AWidth * (FormatTypeBPPTable[APixelFormat.FormatType] shr 3);
  end;
  GetMem(FData, FStride * Height);
end;

destructor TX11Bitmap.Destroy;
begin
  FreeMem(FData);
  inherited Destroy;
end;

procedure TX11Bitmap.Lock(var AData: Pointer; var AStride: LongWord);
begin
  ASSERT(not IsLocked);
  IsLocked := True;

  AData := Data;
  AStride := Stride;
end;

procedure TX11Bitmap.Unlock;
begin
  ASSERT(IsLocked);
  IsLocked := False;
end;


{ TX11Screen }

constructor TX11Screen.Create;
begin
  inherited Create;
  
//  FScreenIndex    := AScreenIndex;
//  FScreenInfo     := XScreenOfDisplay(gApplication.Handle, ScreenIndex);
end;


{ TX11Application }

constructor TX11Application.Create;
begin
  inherited Create;
  
  FDirtyList      := TDirtyList.Create;
end;


destructor TX11Application.Destroy;
var
  i: Integer;
begin
  if Assigned(Forms) then
  begin
    for i := 0 to Forms.Count - 1 do
      TFCustomWindow(Forms[i]).Free;
  end;

  DirtyList.Free;

  if Assigned(FDefaultFont) then
  begin
    if FDefaultFont^.fid <> 0 then
      XUnloadFont(Handle, FDefaultFont^.fid);
    XFreeFontInfo(nil, FDefaultFont, 0);
  end;

  if Assigned(Handle) then
    XCloseDisplay(Handle);

  inherited Destroy;
end;

procedure TX11Application.AddWindow(AWindow: TFCustomWindow);
begin
  Forms.Add(AWindow);
end;

procedure TX11Application.Run;
var
  Event: TXEvent;
  WindowEntry: TFCustomWindow;
begin
  DoBreakRun := False;
  
  while (not (QuitWhenLastWindowCloses and (Forms.Count = 0))) and
   (DoBreakRun = False) do
  begin
    if Assigned(OnIdle) or Assigned(DirtyList.First) then
    begin
      if not XCheckMaskEvent(Handle, MaxInt, @Event) then
      begin
        if Assigned(DirtyList.First) then DirtyList.PaintAll
        else if Assigned(OnIdle) then OnIdle(Self);
        
        continue;
      end;
    end
    else
      XNextEvent(Handle, @Event);

    // if the event filter returns true then it ate the message
    if Assigned(FEventFilter) and FEventFilter(Event) then continue;

    if Forms.Count = 0 then continue;

    // According to a comment in X.h, the valid event types start with 2!
    if Event._type >= 2 then
    begin
      WindowEntry := FindWindowByXID(Event.XAny.Window);

      if Event._type = X.DestroyNotify then
      begin
	Forms.Remove(WindowEntry);
      end
      else if Assigned(WindowEntry) then
      begin
        WindowEntry.Dispatch(Event);
      end
      else
        WriteLn('fpGFX/X11: Received X event "', GetXEventName(Event._type),
	        '" for unknown window');
    end;
  end;
  DoBreakRun := False;
end;


procedure TX11Application.Quit;
begin
  DoBreakRun := True;
end;


function TX11Application.FindWindowByXID(XWindowID: X.TWindow): TFCustomWindow;
var
  i: Integer;
  EndSubSearch: Boolean;
  
  procedure SearchSubWindows(AForm: TFCustomWindow; var ATarget: TFCustomWindow);
  var
    j: Integer;
  begin
    for j := 0 to AForm.ChildWindows.Count - 1 do
    begin
      if EndSubSearch then Exit;
    
      if TFCustomWindow(AForm.ChildWindows[j]).Handle = XWindowID then
      begin
        ATarget := TFCustomWindow(Result.ChildWindows[j]);

        EndSubSearch := True;
        
        Exit;
      end;
      
      SearchSubWindows(TFCustomWindow(AForm.ChildWindows[j]), ATarget);
    end;
  end;
  
begin
  for i := 0 to Forms.Count - 1 do
  begin
    Result := TFCustomWindow(Forms[i]);
    
    if Result.Handle = XWindowID then exit;
    
    EndSubSearch := False;

    SearchSubWindows(TFCustomWindow(Forms[i]), Result);

    if Result.Handle = XWindowID then exit;
  end;
  Result := nil;
end;

procedure TX11Application.Initialize(ADisplayName: String = '');
begin
  if Length(ADisplayName) = 0 then FDisplayName := XDisplayName(nil)
  else FDisplayName := ADisplayName;

  Handle := XOpenDisplay(PChar(DisplayName));

  if not Assigned(Handle) then
    raise EX11Error.CreateFmt(SOpenDisplayFailed, [DisplayName]);

  FDefaultFont := XLoadQueryFont(Handle,
   '-adobe-helvetica-medium-r-normal--*-120-*-*-*-*-iso8859-1');

  if not Assigned(FDefaultFont) then
  begin
    FDefaultFont := XLoadQueryFont(Handle, 'fixed');
    if not Assigned(FDefaultFont) then
      raise EX11Error.Create(SNoDefaultFont);
  end;
end;

{ TX11Window }

{ Note, this only creates a window, it doesn't actually show the window. It
  is still invisible. To make it visible, we need to call Show(). }
constructor TX11Window.Create(AParent: TFCustomWindow;
  AWindowOptions: TGfxWindowOptions);
const
  WindowHints: TXWMHints = (
    flags: InputHint or StateHint or WindowGroupHint;
    input: True;
    initial_state: NormalState;
    icon_pixmap: 0;
    icon_window: 0;
    icon_x: 0;
    icon_y: 0;
    icon_mask: 0;
    window_group: 0;
  );
var
  Colormap: TColormap;
  Attr: TXSetWindowAttributes;
  SizeHints: TXSizeHints;
  ClassHint: PXClassHint;
  lParentHandle: X.TWindow;
  mask: longword;
begin
  inherited Create(AParent, AWindowOptions);

  WindowOptions   := AWindowOptions;
  FParent         := AParent;

  if (not (woX11SkipWMHints in WindowOptions)) and (woWindow in WindowOptions) then
  begin
    if LeaderWindow = 0 then
    begin
      LeaderWindow := XCreateSimpleWindow(GFApplication.Handle,
        XDefaultRootWindow(GFApplication.Handle), 10, 10, 10, 10, 0, 0, 0);

      ClassHint := XAllocClassHint;
      ClassHint^.res_name := 'fpGFX'; // !!! use app name
      ClassHint^.res_class := 'FpGFX';
      XSetWMProperties(GFApplication.Handle, LeaderWindow, nil, nil, nil, 0, nil, nil,
        ClassHint);
      XFree(ClassHint);
      ClientLeaderAtom := XInternAtom(GFApplication.Handle, 'WM_CLIENT_LEADER', False);
    end;
  end;

  Colormap := XDefaultColormap(GFApplication.Handle, XDefaultScreen(GFApplication.Handle));
  Attr.Colormap := Colormap;

  SizeHints.flags     := XUtil.PSize;
  SizeHints.x         := 0;
  SizeHints.y         := 0;
  SizeHints.width     := 200;
  SizeHints.height    := 200;

  { Make sure we use the correct parent handle }
  if FParent <> nil then
    lParentHandle := TX11Window(FParent).Handle
  else
    lParentHandle := XDefaultRootWindow(GFApplication.Handle);

  { setup attributes and masks }
  if (woBorderless in WindowOptions) or (woToolWindow in WindowOptions) or
    (woPopup in WindowOptions) then
  begin
    Attr.Override_Redirect := longbool(1);    // this removes window borders
    mask := CWOverrideRedirect or CWColormap;
  end
  else
  begin
    Attr.Override_Redirect := longbool(0);
    mask := CWColormap;
  end;

  FHandle := XCreateWindow(
    GFApplication.Handle,
    lParentHandle,                      // parent
    SizeHints.x, SizeHints.x,           // position (top, left)
    SizeHints.width, SizeHints.height,  // default size (width, height)
    0,                                  // border size
    CopyFromParent,                     // depth
    InputOutput,                        // class
    XDefaultVisual(GFApplication.Handle, XDefaultScreen(GFApplication.Handle)),  // visual
    mask,
    @Attr);

  if FHandle = 0 then
    raise EX11Error.Create(SWindowCreationFailed);

  XSelectInput(GFApplication.Handle, FHandle, KeyPressMask or KeyReleaseMask
    or ButtonPressMask or ButtonReleaseMask or EnterWindowMask
    or LeaveWindowMask or PointerMotionMask or ExposureMask or FocusChangeMask
    or StructureNotifyMask);
    
  if (not (woX11SkipWMHints in WindowOptions)) and (woWindow in WindowOptions) then
  begin
    XSetStandardProperties(GFApplication.Handle, Handle, nil, nil, 0,
     argv, argc, @SizeHints);
  
    XSetWMNormalHints(GFApplication.Handle, Handle, @SizeHints);
  
    WindowHints.flags := WindowGroupHint;
    WindowHints.window_group := LeaderWindow;
    XSetWMHints(GFApplication.Handle, Handle, @WindowHints);
  
    XChangeProperty(GFApplication.Handle, Handle, ClientLeaderAtom, 33, 32,
     PropModeReplace, @LeaderWindow, 1);
  
     // We want to get a Client Message when the user tries to close this window
    if GFApplication.FWMProtocols = 0 then
     GFApplication.FWMProtocols := XInternAtom(GFApplication.Handle, 'WM_PROTOCOLS', False);
    if GFApplication.FWMDeleteWindow = 0 then
     GFApplication.FWMDeleteWindow := XInternAtom(GFApplication.Handle, 'WM_DELETE_WINDOW', False);
  
     // send close event instead of quitting the whole application...
     XSetWMProtocols(GFApplication.Handle, FHandle, @GFApplication.FWMDeleteWindow, 1);
   end;

  FCanvas := TX11WindowCanvas.Create(Colormap, Handle, GFApplication.FDefaultFont);
end;


destructor TX11Window.Destroy;
begin
  if Assigned(OnClose) then
    OnClose(Self);

  GFApplication.DirtyList.ClearQueueForWindow(Self);

  XDestroyWindow(GFApplication.Handle, Handle);
  Canvas.Free;

  GFApplication.Forms.Remove(Self);

  if FCurCursorHandle <> 0 then
    XFreeCursor(GFApplication.Handle, FCurCursorHandle);

  inherited Destroy;
end;


procedure TX11Window.DefaultHandler(var Message);
begin
  WriteLn('fpGFX/X11: Unhandled X11 event received: ',
    GetXEventName(TXEvent(Message)._type));
end;


procedure TX11Window.SetPosition(const APosition: TPoint);
var
  Supplied: PtrInt;
  SizeHints: PXSizeHints;
begin
  SizeHints := XAllocSizeHints;
  XGetWMNormalHints(GFApplication.Handle, Handle, SizeHints, @Supplied);
  SizeHints^.flags := SizeHints^.flags or PPosition;
  SizeHints^.x := APosition.x;
  SizeHints^.y := APosition.y;
  XSetWMNormalHints(GFApplication.Handle, Handle, SizeHints);
  XFree(SizeHints);
  XMoveWindow(GFApplication.Handle, Handle, APosition.x, APosition.y);
end;


procedure TX11Window.SetSize(const ASize: TSize);
begin
  // !!!: Implement this properly
  WriteLn('fpGFX/X11: TXWindow.SetSize is not properly implemented yet');
  SetClientSize(ASize);
end;


procedure TX11Window.SetMinMaxSize(const AMinSize, AMaxSize: TSize);
begin
  // !!!: Implement this properly
  WriteLn('fpGFX/X11: TXWindow.SetMinMaxSize is not properly implemented yet');
  SetMinMaxClientSize(AMinSize, AMaxSize);
end;


procedure TX11Window.SetClientSize(const ASize: TSize);
var
  ChangeMask: Cardinal;
  Changes: TXWindowChanges;
begin
  ChangeMask := 0;

  if ASize.cx <> ClientWidth then
  begin
    ChangeMask := CWWidth;
    Changes.Width := ASize.cx;
  end;

  if ASize.cy <> ClientHeight then
  begin
    ChangeMask := ChangeMask or CWHeight;
    Changes.Height := ASize.cy;
  end;

  if ChangeMask <> 0 then
    XConfigureWindow(GFApplication.Handle, Handle, ChangeMask, @Changes);
end;


procedure TX11Window.SetMinMaxClientSize(const AMinSize, AMaxSize: TSize);
var
  Supplied: PtrInt;
  SizeHints: PXSizeHints;
begin
  CanMaximize := (AMaxSize.cx = 0) or (AMaxSize.cy = 0) or
    (AMaxSize.cx > AMinSize.cx) or (AMaxSize.cy > AMinSize.cy);
  UpdateMotifWMHints;

  SizeHints := XAllocSizeHints;
  XGetWMNormalHints(GFApplication.Handle, Handle, SizeHints, @Supplied);
  with SizeHints^ do
  begin
    if (AMinSize.cx > 0) or (AMinSize.cy > 0) then
    begin
      flags := flags or PMinSize;
      min_width := AMinSize.cx;
      min_height := AMinSize.cy;
    end else
      flags := flags and not PMinSize;

    if (AMaxSize.cx > 0) or (AMaxSize.cy > 0) then
    begin
      flags := flags or PMaxSize;
      if AMaxSize.cx > 0 then
        max_width := AMaxSize.cx
      else
        max_width := 32767;
      if AMaxSize.cy > 0 then
        max_height := AMaxSize.cy
      else
        max_height := 32767;
    end else
      flags := flags and not PMaxSize;
  end;

  XSetWMNormalHints(GFApplication.Handle, Handle, SizeHints);
  XFree(SizeHints);
end;


{ Makes the window visible and raises it to the top of the stack. }
procedure TX11Window.Show;
begin
  XMapRaised(GFApplication.Handle, Handle);
end;


procedure TX11Window.Invalidate(const ARect: TRect);
begin
  GFApplication.DirtyList.AddRect(Self, ARect);
end;


procedure TX11Window.PaintInvalidRegion;
begin
  GFApplication.DirtyList.PaintQueueForWindow(Self);
end;


procedure TX11Window.CaptureMouse;
begin
  XGrabPointer(GFApplication.Handle, Handle, False, ButtonPressMask or
    ButtonReleaseMask or EnterWindowMask or LeaveWindowMask or
    PointerMotionMask, GrabModeAsync, GrabModeAsync, 0, 0, CurrentTime);
end;


procedure TX11Window.ReleaseMouse;
begin
  XUngrabPointer(GFApplication.Handle, CurrentTime);
end;


// protected methods

function TX11Window.GetTitle: String;
var
  s: PChar;
begin
  XFetchName(GFApplication.Handle, Handle, @s);
  Result := s;
  XFree(s);
end;


procedure TX11Window.SetTitle(const ATitle: String);
begin
  XStoreName(GFApplication.Handle, Handle, PChar(ATitle));
end;


procedure TX11Window.DoSetCursor;
const
  CursorTable: array[TGfxCursor] of Integer = (
    -1,			// crDefault
    -2,			// crNone	!!!: not implemented
    -1,			// crArrow
    34,			// crCross
    152,		// crIBeam
    52,			// crSize
    116,		// crSizeNS
    108,		// crSizeWE
    114,		// crUpArrow
    150,		// crHourGlass
    0,			// crNoDrop
    92);		// crHelp
var
  ID: Integer;
begin
  if FCurCursorHandle <> 0 then
    XFreeCursor(GFApplication.Handle, FCurCursorHandle);
  ID := CursorTable[Cursor];
  if ID = -1 then
    FCurCursorHandle := 0
  else
    FCurCursorHandle := XCreateFontCursor(GFApplication.Handle, ID);
  XDefineCursor(GFApplication.Handle, Handle, FCurCursorHandle);
end;


function TX11Window.ConvertShiftState(AState: Cardinal): TShiftState;
begin
  Result := [];
  if (AState and Button1Mask) <> 0 then
    Include(Result, ssLeft);
  if (AState and Button2Mask) <> 0 then
    Include(Result, ssMiddle);
  if (AState and Button3Mask) <> 0 then
    Include(Result, ssRight);
  if (AState and ShiftMask) <> 0 then
    Include(Result, ssShift);
  if (AState and LockMask) <> 0 then
    Include(Result, ssCaps);
  if (AState and ControlMask) <> 0 then
    Include(Result, ssCtrl);
  if (AState and Mod1Mask) <> 0 then
    Include(Result, ssAlt);
  if (AState and Mod2Mask) <> 0 then
    Include(Result, ssNum);
  if (AState and Mod4Mask) <> 0 then
    Include(Result, ssSuper);
  if (AState and Mod5Mask) <> 0 then
    Include(Result, ssScroll);
  if (AState and (1 shl 13)) <> 0 then
    Include(Result, ssAltGr);
end;

function TX11Window.KeySymToKeycode(KeySym: TKeySym): Word;
const
  Table_20aX: array[$20a0..$20ac] of Word = (keyEcuSign, keyColonSign,
    keyCruzeiroSign, keyFFrancSign, keyLiraSign, keyMillSign, keyNairaSign,
    keyPesetaSign, keyRupeeSign, keyWonSign, keyNewSheqelSign, keyDongSign,
    keyEuroSign);
  Table_feXX: array[$fe50..$fe60] of Word = (keyDeadGrave, keyDeadAcute,
    keyDeadCircumflex, keyDeadTilde, keyDeadMacron,keyDeadBreve,
    keyDeadAbovedot, keyDeadDiaeresis, keyDeadRing, keyDeadDoubleacute,
    keyDeadCaron, keyDeadCedilla, keyDeadOgonek, keyDeadIota,
    keyDeadVoicedSound, keyDeadSemivoicedSound, keyDeadBelowdot);
  Table_ff5X: array[$ff50..$ff58] of Word = (keyHome, keyLeft, keyUp, keyRight,
    keyDown, keyPrior, keyNext, keyEnd, keyBegin);
  Table_ff6X: array[$ff60..$ff6b] of Word = (keySelect, keyPrintScreen,
    keyExecute, keyNIL, keyInsert, keyUndo, keyRedo, keyMenu, keyFind,
    keyCancel, keyHelp, keyBreak);
  Table_ff9X: array[$ff91..$ff9f] of Word = (keyPF1, keyPF2, keyPF3, keyPF4,
    keyP7, keyP4, keyP8, keyP6, keyP2, keyP9, keyP3, keyP1, keyP5, keyP0,
    keyPDecimal);
  Table_ffeX: array[$ffe1..$ffee] of Word = (keyShiftL, keyShiftR, keyCtrlL,
    keyCtrlR, keyCapsLock, keyShiftLock, keyMetaL, keyMetaR, keyAltL, keyAltR,
    keySuperL, keySuperR, keyHyperL, keyHyperR);
begin
  case KeySym of
    0..Ord('a')-1, Ord('z')+1..$bf, $f7:
      Result := KeySym;
    Ord('a')..Ord('z'), $c0..$f6, $f8..$ff:
      Result := KeySym - 32;
    $20a0..$20ac: Result := Table_20aX[KeySym];
    $fe20: Result := keyTab;
    $fe50..$fe60: Result := Table_feXX[KeySym];
    $ff08: Result := keyBackspace;
    $ff09: Result := keyTab;
    $ff0a: Result := keyLinefeed;
    $ff0b: Result := keyClear;
    $ff0d: Result := keyReturn;
    $ff13: Result := keyPause;
    $ff14: Result := keyScrollLock;
    $ff15: Result := keySysRq;
    $ff1b: Result := keyEscape;
    $ff50..$ff58: Result := Table_ff5X[KeySym];
    $ff60..$ff6b: Result := Table_ff6X[KeySym];
    $ff7e: Result := keyModeSwitch;
    $ff7f: Result := keyNumLock;
    $ff80: Result := keyPSpace;
    $ff89: Result := keyPTab;
    $ff8d: Result := keyPEnter;
    $ff91..$ff9f: Result := Table_ff9X[KeySym];
    $ffaa: Result := keyPAsterisk;
    $ffab: Result := keyPPlus;
    $ffac: Result := keyPSeparator;
    $ffad: Result := keyPMinus;
    $ffae: Result := keyPDecimal;
    $ffaf: Result := keyPSlash;
    $ffb0..$ffb9: Result := keyP0 + KeySym - $ffb0;
    $ffbd: Result := keyPEqual;
    $ffbe..$ffe0: Result := keyF1 + KeySym - $ffbe;
    $ffe1..$ffee: Result := Table_ffeX[KeySym];
    $ffff: Result := keyDelete;
  else
    Result := keyNIL;
  end;
{$IFDEF Debug}
  if Result = keyNIL then
    WriteLn('fpGFX/X11: Unknown KeySym: $', IntToHex(KeySym, 4));
{$ENDIF}
end;


procedure TX11Window.UpdateMotifWMHints;
type
  PMotifWmHints = ^TMotifWmHints;
  TMotifWmHints = packed record
    Flags, Functions, Decorations: LongWord;
    InputMode: LongInt;
    Status: LongWord;
  end;
const
  MWM_HINTS_FUNCTIONS = 1;
  MWM_HINTS_DECORATIONS = 2;
  FuncAll = 1;
  FuncResize = 2;
  FuncMove = 4;
  FuncMinimize = 8;
  FuncMaximize = 16;
  FuncClose = 32;
  DecorAll = 1;
  DecorBorder = 2;
  DecorResizeH = 4;
  DecorTitle = 8;
  DecorMenu = 16;
  DecorMinimize = 32;
  DecorMaximize = 64;
var
  PropType: TAtom;
  PropFormat: LongInt;
  PropItemCount, PropBytesAfter: LongWord;
  Hints: PMotifWmHints;
  NewHints: TMotifWmHints;
begin
  if GFApplication.FWMHints = 0 then
    GFApplication.FWMHints :=
      XInternAtom(GFApplication.Handle, '_MOTIF_WM_HINTS', False);

  XGetWindowProperty(GFApplication.Handle, Handle,
    GFApplication.FWMHints, 0, 5, False, AnyPropertyType, @PropType,
    @PropFormat, @PropItemCount, @PropBytesAfter, @Hints);

  NewHints.Flags := MWM_HINTS_FUNCTIONS or MWM_HINTS_DECORATIONS;
  NewHints.Functions := FuncResize or FuncMove or FuncMinimize or FuncClose;

  if (woToolWindow in WindowOptions) or (woWindow in WindowOptions) or
   (woPopup in WindowOptions) then
    NewHints.Decorations := DecorBorder or DecorTitle or DecorMenu or DecorMinimize
  else
    NewHints.Decorations := 0;
  if CanMaximize then
  begin
    NewHints.Functions := NewHints.Functions or FuncMaximize;
    NewHints.Decorations := NewHints.Decorations or DecorMaximize;
  end;

  if Assigned(Hints) then
  begin
    Hints^.Flags := Hints^.Flags or NewHints.Flags;
    Hints^.Decorations := NewHints.Decorations;
    Hints^.Functions := NewHints.Functions;
  end else
    Hints := @NewHints;

  XChangeProperty(GFApplication.Handle, Handle,
    GFApplication.FWMHints, GFApplication.FWMHints,
    32, PropModeReplace, Pointer(Hints), 5);
  if Hints <> @NewHints then
    XFree(Hints);
end;


// private methods

const
  ButtonTable: array[1..3] of TMouseButton = (mbLeft, mbMiddle, mbRight);


function TX11Window.StartComposing(const Event: TXKeyEvent): TKeySym;
begin
  SetLength(FComposeBuffer,
    XLookupString(@Event, @FComposeBuffer[1],
      SizeOf(FComposeBuffer) - 1, @Result, @FComposeStatus));
end;


procedure TX11Window.EndComposing;
var
  i: Integer;
begin
  if Assigned(OnKeyChar) then
    for i := 1 to Length(FComposeBuffer) do
      OnKeyChar(Self, FComposeBuffer[i]);
end;


procedure TX11Window.KeyPressed(var Event: TXKeyPressedEvent);
var
  KeySym: TKeySym;
begin
  KeySym := StartComposing(Event);
  if Assigned(OnKeyPressed) then
    OnKeyPressed(Self, KeySymToKeycode(KeySym), ConvertShiftState(Event.State));

  if (Event.State and (ControlMask or Mod1Mask)) = 0 then
    EndComposing;
end;


procedure TX11Window.KeyReleased(var Event: TXKeyReleasedEvent);
var
  KeySym: TKeySym;
begin
  KeySym := StartComposing(Event);
  if Assigned(OnKeyReleased) then
    OnKeyReleased(Self, KeySymToKeycode(KeySym),
      ConvertShiftState(Event.State));
  // Do not call EndComposing, as this would generate duplicate KeyChar events!
end;


procedure TX11Window.ButtonPressed(var Event: TXButtonPressedEvent);
var
  Sum: Integer;
  NewEvent: TXEvent;
begin
  case Event.Button of
    Button1..Button3:
      if Assigned(OnMousePressed) then
        OnMousePressed(Self, ButtonTable[Event.Button],
          ConvertShiftState(Event.State), Point(Event.x, Event.y));
    Button4, Button5:		// Mouse wheel message
      begin
        if Event.Button = Button4 then
          Sum := -1
        else
          Sum := 1;

	// Check for other mouse wheel messages in the queue
	while XCheckTypedWindowEvent(GFApplication.Handle, Handle,
	  X.ButtonPress, @NewEvent) do
	begin
	  if NewEvent.xbutton.Button = 4 then
	    Dec(Sum)
	  else if NewEvent.xbutton.Button = 5 then
	    Inc(Sum)
	  else
	  begin
	    XPutBackEvent(GFApplication.Handle, @NewEvent);
	    break;
	  end;
	end;

        if Assigned(OnMouseWheel) then
          OnMouseWheel(Self, ConvertShiftState(Event.State),
	    Sum, Point(Event.x, Event.y));
      end;
  end;
end;


procedure TX11Window.ButtonReleased(var Event: TXButtonReleasedEvent);
begin
  if (Event.Button >= 1) and (Event.Button <= 3) and
    Assigned(OnMouseReleased) then
    OnMouseReleased(Self, ButtonTable[Event.Button],
      ConvertShiftState(Event.State), Point(Event.x, Event.y));
end;


procedure TX11Window.EnterWindow(var Event: TXEnterWindowEvent);
begin
  if Assigned(OnMouseEnter) then
    OnMouseEnter(Self, ConvertShiftState(Event.State), Point(Event.x, Event.y));
end;


procedure TX11Window.LeaveWindow(var Event: TXLeaveWindowEvent);
begin
  if Assigned(OnMouseEnter) then
    OnMouseLeave(Self);
end;


procedure TX11Window.PointerMoved(var Event: TXPointerMovedEvent);
begin
  if Assigned(OnMouseMove) then
    OnMouseMove(Self, ConvertShiftState(Event.State), Point(Event.x, Event.y));
end;


procedure TX11Window.Expose(var Event: TXExposeEvent);
{var
  IsNotEmpty: Boolean;
begin
WriteLn('Expose');
  if Assigned(OnPaint) then
    with Event do
    begin
      if not IsExposing then
      begin
        IsExposing := True;
	Canvas.SaveState;
	Canvas.EmptyClipRect;
      end;
      IsNotEmpty := Canvas.UnionClipRect(Rect(x, y, x + Width, y + Height));
      if Count = 0 then
      begin
        if IsNotEmpty then
	  OnPaint(Self, Canvas.GetClipRect);
	IsExposing := False;
	Canvas.RestoreState;
      end;
    end;
end;}
var
  r: TRect;
begin
  with Event do
    r := Rect(x, y, x + Width, y + Height);
  GFApplication.DirtyList.AddRect(Self, r);
end;


procedure TX11Window.FocusIn(var Event: TXFocusInEvent);
begin
  if Assigned(OnFocusIn) then
    OnFocusIn(Self);
end;


procedure TX11Window.FocusOut(var Event: TXFocusOutEvent);
begin
  if Assigned(OnFocusOut) then
    OnFocusOut(Self);
end;


procedure TX11Window.Map(var Event: TXMapEvent);
begin
  if Assigned(OnShow) then
    OnShow(Self);
end;


procedure TX11Window.Unmap(var Event: TXUnmapEvent);
begin
  if Assigned(OnHide) then
    OnHide(Self);
end;


procedure TX11Window.Reparent(var Event: TXReparentEvent);
begin
  if Assigned(OnCreate) then
    OnCreate(Self);
end;


procedure TX11Window.Configure(var Event: TXConfigureEvent);
begin
  while XCheckTypedWindowEvent(GFApplication.Handle, Handle,
    X.ConfigureNotify, @Event) do;

  if (Event.x <> Left) or (Event.y <> Top) then
  begin
    FLeft := Event.x;
    FTop := Event.y;
    if Assigned(OnMove) then
      OnMove(Self);
  end;
  if (Event.Width <> Width) or (Event.Height <> Height) then
  begin
  // !!!: The following 2 lines are _quite_ wrong... :)
    FWidth := Event.Width;
    FHeight := Event.Height;
    FClientWidth := Event.Width;
    FClientHeight := Event.Height;
    TX11Canvas(Canvas).Resized(ClientWidth, ClientHeight);
    if Assigned(OnResize) then
      OnResize(Self);
  end;
end;


procedure TX11Window.ClientMessage(var Event: TXClientMessageEvent);
begin
  if Event.message_type = GFApplication.FWMProtocols then
    if Event.Data.l[0] = GFApplication.FWMDeleteWindow then
    begin
      if CanClose then
        Free;
    end else
      WriteLn('fpGFX/X11: Unknown client protocol message: ', Event.Data.l[0])
  else
    WriteLn('fpGFX/X11: Unknown client message: ', Event.message_type);
end;

{ Global utility functions }

function RectToXRect(const ARect: TRect): TXRectangle;
begin
  Result.x      := ARect.Left;
  Result.y      := ARect.Top;
  Result.width  := ARect.Right - ARect.Left;
  Result.height := ARect.Bottom - ARect.Top;
end;


function XRectToRect(const ARect: TXRectangle): TRect;
begin
  Result.Left   := ARect.x;
  Result.Top    := ARect.y;
  Result.Right  := ARect.x + ARect.width;
  Result.Bottom := ARect.y + ARect.height;
end;


function GetXEventName(Event: LongInt): String;
const
  EventNames: array[2..34] of String = (
    'KeyPress', 'KeyRelease', 'ButtonPress', 'ButtonRelease', 'MotionNotify',
    'EnterNotify', 'LeaveNotify', 'FocusIn', 'FocusOut', 'KeymapNotify',
    'Expose', 'GraphicsExpose', 'NoExpose', 'VisibilityNotify', 'CreateNotify',
    'DestroyNotify', 'UnmapNotify', 'MapNotify', 'MapRequest', 'ReparentNotify',
    'ConfigureNotify', 'ConfigureRequest', 'GravityNotify', 'ResizeRequest',
    'CirculateNotify', 'CirculateRequest', 'PropertyNotify', 'SelectionClear',
    'SelectionRequest', 'SelectionNotify', 'ColormapNotify', 'ClientMessage',
    'MappingNotify');
begin
  if (Event >= Low(EventNames)) and (Event <= High(EventNames)) then
    Result := EventNames[Event]
  else
    Result := '#' + IntToStr(Event);
end;

end.


