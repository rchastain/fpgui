{
    fpGUI  -  Free Pascal GUI Library

    Copyright (C) 2006 - 2007 See the file AUTHORS.txt, included in this
    distribution, for details of the copyright.

    See the file COPYING.modifiedLGPL, included in this distribution,
    for details about redistributing fpGUI.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

    Description:
      A lot of the main code is here.
}


unit vfddesigner;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  SysUtils,
  gfxbase,
  fpgfx,
  gfx_widget,
  gui_form,
  gui_dialogs,
  gui_label,
  gui_edit,
  gui_button,
  gui_listbox,
  gui_memo,
  gui_combobox,
  gui_checkbox,
  vfdresizer,
  vfdforms,
  vfdeditors,
  vfdwidgetclass,
  vfdwidgets,
  newformdesigner;

type

  TOtherWidget = class(TfpgWidget)
  protected
    FFont: TfpgFont;
    procedure HandlePaint; override;
  public
    wgClassName: string;
    constructor Create(AOwner: TComponent); override;
  end;


  TFormDesigner = class;


  TDesignedForm = class(TfpgForm)
  public
    procedure AfterCreate; override;
  end;


  TWidgetDesigner = class(TObject)
  private
    procedure   SetSelected(const AValue: boolean);
  public
    FFormDesigner: TFormDesigner;
    FWidget: TfpgWidget;
    FVFDClass: TVFDWidgetClass;
    FSelected: boolean;
    resizer: array[1..8] of TwgResizer;
    other: TStringList;
    constructor Create(AFormDesigner: TFormDesigner; wg: TfpgWidget; wgc: TVFDWidgetClass);
    destructor  Destroy; override;
    property    Selected: boolean read FSelected write SetSelected;
    property    Widget: TfpgWidget read FWidget;
    procedure   UpdateResizerPositions;
    property    FormDesigner: TFormDesigner read FFormDesigner;
  end;


  TFormDesigner = class(TObject)
  protected
    FWidgets: TList;
    FForm: TDesignedForm;
    FFormOther: string;
    FDragging: boolean;
    FDragPosX,
    FDragPosY: TfpgCoord;
    FWasDrag: boolean;
  protected
    // messages of the designed widgets
    procedure   MsgMouseDown(var msg: TfpgMessageRec); message FPGM_MOUSEDOWN;
    procedure   MsgMouseUp(var msg: TfpgMessageRec); message FPGM_MOUSEUP;
    procedure   MsgMouseMove(var msg: TfpgMessageRec); message FPGM_MOUSEMOVE;
    procedure   MsgKeyPress(var msg: TfpgMessageRec); message FPGM_KEYPRESS;
    procedure   MsgMove(var msg: TfpgMessageRec); message FPGM_MOVE;
    procedure   MsgResize(var msg: TfpgMessageRec); message FPGM_RESIZE;
    procedure   MsgActivate(var msg: TfpgMessageRec); message FPGM_ACTIVATE;
    procedure   DesignerKeyPress(var keycode: word; var shiftstate: TShiftState; var consumed: boolean);
  public
    OneClickMove: boolean; // the widgets can be selected and dragged within one click
    constructor Create;
    destructor  Destroy; override;
    procedure   ClearForm;
    procedure   DefaultHandler(var msg); override;
    procedure   Show;
    function    AddWidget(wg: TfpgWidget; wgc: TVFDWidgetClass): TWidgetDesigner;
    function    WidgetDesigner(wg: TfpgWidget): TWidgetDesigner;
    function    FindWidgetByName(const wgname: string): TfpgWidget;
    procedure   DeSelectAll;
    procedure   SelectAll;
    procedure   SelectNextWidget(fw: boolean);
    procedure   MoveResizeWidgets(dx, dy, dw, dh: integer);
    procedure   DeleteWidgets;
    procedure   EditWidgetOrder;
    procedure   EditTabOrder;
//    procedure PutControlByName(x, y: integer; cname: string);
    procedure   InsertWidget(pwg: TfpgWidget; x, y: integer; wgc: TVFDWidgetClass);
    procedure   OnPaletteChange(Sender: TObject);
    procedure   UpdatePropWin;
    procedure   OnPropTextChange(Sender: TObject);
    procedure   OnPropNameChange(Sender: TObject);
    procedure   OnPropPosEdit(Sender: TObject);
    procedure   OnOtherChange(Sender: TObject);
    procedure   OnAnchorChange(Sender: TObject);
    procedure   OnEditWidget(Sender: TObject);
    function    GenerateNewName(namebase: string): string;
    procedure   RunWidgetEditor(wgd: TWidgetDesigner; wg: TfpgWidget);
    function    GetFormSourceDecl: string;
    function    GetFormSourceImpl: string;
    function    GetWidgetSourceImpl(wd: TWidgetDesigner; ident: string): string;
    property    Form: TDesignedForm read FForm;
    property    FormOther: string read FFormOther write FFormOther;
  end;


implementation

uses
  vfdmain, TypInfo;

type
  // used to get to SetDesigning() in Form Designer
  TComponentFriendClass = class(TComponent);

{ TWidgetDesigner }

procedure TWidgetDesigner.SetSelected(const AValue: boolean);
var
  n: integer;
begin
  if FSelected = AValue then
    Exit;
  FSelected := AValue;

  if FSelected then
    Widget.MouseCursor := mcMove
  else
    Widget.MouseCursor := mcDefault;

  for n := 1 to 8 do
    if FSelected then
      resizer[n] := TwgResizer.Create(self, n)
    else
    begin
      if resizer[n] <> nil then
        resizer[n].Free;
      resizer[n] := nil;
    end;

  UpdateResizerPositions;

  if FSelected and Widget.Parent.HasHandle then
    for n := 1 to 8 do
      resizer[n].Show;
end;

constructor TWidgetDesigner.Create(AFormDesigner: TFormDesigner; wg: TfpgWidget; wgc: TVFDWidgetClass);
var
  n: integer;
begin
  FFormDesigner := AFormDesigner;
  FWidget       := wg;
  FVFDClass     := wgc;
  for n := 1 to 8 do
    resizer[n] := nil;
  FSelected := False;
  wg.MouseCursor := mcDefault;
  other := TStringList.Create;
end;

destructor TWidgetDesigner.Destroy;
var
  n: integer;
begin
  for n := 1 to 8 do
    if resizer[n] <> nil then
      resizer[n].Free;
  other.Free;
  inherited Destroy;
end;

procedure TWidgetDesigner.UpdateResizerPositions;
var
  n: integer;
  rs: TwgResizer;
begin
  if not FSelected then
    Exit;

  for n := 1 to 8 do
  begin
    rs := resizer[n];

    if rs <> nil then
    begin
      case n of
        1:
        begin
          rs.left := Widget.left - 2;
          rs.Top  := Widget.Top - 2;
        end;
        2:
        begin
          rs.Top  := Widget.Top - 2;
          rs.left := Widget.left + Widget.Width div 2 - 2;
        end;
        3:
        begin
          rs.Top  := Widget.Top - 2;
          rs.left := Widget.left + Widget.Width - 1 - 2;
        end;
        4:
        begin
          rs.Top  := Widget.Top + Widget.Height div 2 - 2;
          rs.left := Widget.left + Widget.Width - 1 - 2;
        end;
        5:
        begin
          rs.Top  := Widget.Top + Widget.Height - 1 - 2;
          rs.left := Widget.left + Widget.Width - 1 - 2;
        end;
        6:
        begin
          rs.Top  := Widget.Top + Widget.Height - 1 - 2;
          rs.left := Widget.left + Widget.Width div 2 - 2;
        end;
        7:
        begin
          rs.Top  := Widget.Top + Widget.Height - 1 - 2;
          rs.left := Widget.left - 2;
        end;
        8:
        begin
          rs.Top  := Widget.Top + Widget.Height div 2 - 2;
          rs.left := Widget.left - 2;
        end;
      end; // case
      if rs.HasHandle then
        rs.UpdateWindowPosition;
    end;
  end;

end;

{ TFormDesigner }

procedure TFormDesigner.MsgMouseDown(var msg: TfpgMessageRec);
var
  wgd: TWidgetDesigner;
  shift: boolean;
begin
//  writeln('TFormDesigner.MsgMouseDown');
  msg.Stop  := True;
  FDragging := True;
  FWasDrag  := False;
  FDragPosX := msg.Params.mouse.x;
  FDragPosy := msg.Params.mouse.y;

  if msg.dest = FForm then
    Exit;

  wgd := WidgetDesigner(TfpgWidget(msg.dest));
  if wgd = nil then
    Exit;

  if not OneClickMove then
    Exit; // this Exit disables one click move

  shift := (ssShift in msg.Params.mouse.shiftstate);

  if shift then
    Exit;

  if not wgd.Selected then
  begin
    DeSelectAll;
    wgd.Selected := True;
    UpdatePropWin;
  end;
end;

procedure TFormDesigner.MsgMouseUp(var msg: TfpgMessageRec);
var
  wgd: TWidgetDesigner;
  wgc: TVFDWidgetClass;
  pwg: TfpgWidget;
  shift: boolean;
  x, y: integer;
begin
//  writeln('TFormDesigner.MsgMouseUp');
  msg.Stop  := True;
  FDragging := False;

  shift := (ssShift in msg.Params.mouse.shiftstate);

  wgc := frmMain.SelectedWidget;
  pwg := TfpgWidget(msg.dest);
  wgd := WidgetDesigner(TfpgWidget(msg.dest));
  if wgd = nil then
    pwg := FForm
  else if not wgd.FVFDClass.Container then
    wgc := nil;

  if wgc <> nil then
  begin
    DeSelectAll;

    if wgc <> nil then
    begin
      x := msg.Params.mouse.x;
      y := msg.Params.mouse.y;

      if maindsgn.GridResolution > 1 then
      begin
        x := x - x mod maindsgn.GridResolution;
        y := y - y mod maindsgn.GridResolution;
      end;

      InsertWidget(pwg, x, y, wgc);

      if not shift then
      begin
        FForm.MouseCursor      := mcDefault;
        frmMain.SelectedWidget := nil;
      end;
    end;
  end
  else
  begin
    wgd := WidgetDesigner(TfpgWidget(msg.dest));
    if wgd = nil then
    begin
      DeSelectAll;
      UpdatePropWin;
      Exit;
    end;

    if not shift then
    begin
      if not wgd.Selected then
        DeSelectAll;
      wgd.Selected := True;
    end
    else
      wgd.Selected := not wgd.Selected;
  end;

  UpdatePropWin;
end;

procedure TFormDesigner.MsgMouseMove(var msg: TfpgMessageRec);
var
  dx, dy: integer;
  wgd: TWidgetDesigner;
begin
  msg.Stop  := True;
  if not FDragging then
    Exit;

  FWasDrag := True;

  dx := msg.Params.mouse.x - FDragPosX;
  dy := msg.Params.mouse.y - FDragPosY;

  wgd := WidgetDesigner(TfpgWidget(msg.dest));
  if (wgd = nil) or (not wgd.Selected) then
    Exit;

  if maindsgn.GridResolution > 1 then
  begin
    dx := dx - (dx mod maindsgn.GridResolution);
    dy := dy - (dy mod maindsgn.GridResolution);
  end;

  MoveResizeWidgets(dx, dy, 0, 0);
end;

procedure TFormDesigner.MsgKeyPress(var msg: TfpgMessageRec);
var
  key: word;
  ss: TShiftState;
  consumed: boolean;
begin
  key := msg.params.keyboard.keycode;
  ss  := msg.params.keyboard.shiftstate;

  msg.Stop := True;
  consumed := False;

  DesignerKeyPress(key, ss, consumed);
end;

procedure TFormDesigner.MsgMove(var msg: TfpgMessageRec);
begin
  if msg.dest = FForm then
    UpdatePropWin;
  msg.Stop  := True;
end;

procedure TFormDesigner.MsgResize(var msg: TfpgMessageRec);
begin
  msg.Stop := True;
  if msg.dest = FForm then
  begin
    DeSelectAll; // because of the anchorings
    UpdatePropWin;
  end;
end;

constructor TFormDesigner.Create;
begin
  FWidgets := TList.Create;
  FWasDrag := False;

  OneClickMove := True; //false;

  FForm      := TDesignedForm.Create(nil);
  FForm.FormDesigner := self;
  FForm.Name := maindsgn.NewFormName;
  FForm.WindowTitle := FForm.Name;
  FFormOther := '';
end;

destructor TFormDesigner.Destroy;
var
  n: integer;
begin
  for n := 0 to FWidgets.Count - 1 do
    TObject(FWidgets.Items[n]).Free;
  FWidgets.Free;

  if FForm <> nil then
    FForm.Free;
  inherited Destroy;
end;

procedure TFormDesigner.ClearForm;
var
  n: integer;
begin
  for n := 0 to FWidgets.Count - 1 do
  begin
    TWidgetDesigner(FWidgets.Items[n]).Widget.Free;
    TObject(FWidgets.Items[n]).Free;
  end;
  FWidgets.Clear;
end;

procedure TFormDesigner.DefaultHandler(var msg);
begin
  //Writeln('Designer message: ',TMessageRec(msg).msgcode,' from ',TMessageRec(msg).dest.ClassName);
end;

procedure TFormDesigner.Show;
begin
  FForm.Show;
  UpdatePropWin;
end;

function TFormDesigner.AddWidget(wg: TfpgWidget; wgc: TVFDWidgetClass): TWidgetDesigner;
var
  cd: TWidgetDesigner;
begin
//  writeln('TFormDesigner.AddWidget');
  cd     := TWidgetDesigner.Create(self, wg, wgc);
  FWidgets.Add(cd);
  //cd.Selected := true;
  if wg is TDesignedForm then
    TDesignedForm(wg).FormDesigner := self;
  Result := cd;
end;

function TFormDesigner.WidgetDesigner(wg: TfpgWidget): TWidgetDesigner;
var
  n: integer;
  cd: TWidgetDesigner;
begin
  Result := nil;
  for n := 0 to FWidgets.Count - 1 do
  begin
    cd := TWidgetDesigner(FWidgets.Items[n]);
    if cd.Widget = wg then
    begin
      Result := cd;
      Exit;
    end;
  end;
end;

procedure TFormDesigner.DeSelectAll;
var
  n: integer;
  cd: TWidgetDesigner;
begin
  for n := 0 to FWidgets.Count - 1 do
  begin
    cd          := TWidgetDesigner(FWidgets.Items[n]);
    cd.Selected := False;
  end;
end;

procedure TFormDesigner.SelectAll;
var
  n: integer;
  cd: TWidgetDesigner;
begin
  for n := 0 to FWidgets.Count - 1 do
  begin
    cd          := TWidgetDesigner(FWidgets.Items[n]);
    cd.Selected := True;
  end;
end;

procedure TFormDesigner.SelectNextWidget(fw: boolean);
var
  n, dir: integer;
  cd, scd: TWidgetDesigner;
begin
  if FWidgets.Count < 1 then
    Exit;

  if fw then
  begin
    n   := 0;
    dir := 1;
  end
  else
  begin
    dir := -1;
    n   := FWidgets.Count - 1;
  end;

  scd := TWidgetDesigner(FWidgets.Items[n]);

  while (n >= 0) and (n < FWidgets.Count) do
  begin
    cd := TWidgetDesigner(FWidgets.Items[n]);
    if cd.Selected then
    begin
      if fw then
      begin
        if n < FWidgets.Count - 1 then
          scd := TWidgetDesigner(FWidgets.Items[n + 1]);
      end
      else if n > 0 then
        scd := TWidgetDesigner(FWidgets.Items[n - 1]);
      break;
    end;
    n := n + dir;
  end;
  DeSelectAll;
  scd.Selected := True;
  UpdatePropWin;
end;

procedure TFormDesigner.MoveResizeWidgets(dx, dy, dw, dh: integer);
var
  n: integer;
  cd: TWidgetDesigner;
begin
  for n := 0 to FWidgets.Count - 1 do
  begin
    cd := TWidgetDesigner(FWidgets.Items[n]);
    if cd.Selected then
    begin
//      if maindsgn.GridResolution > 1 then;
      cd.Widget.MoveAndResizeBy(dx, dy, dw, dh);
      cd.UpdateResizerPositions;
    end;
  end;
  UpdatePropWin;
end;

procedure TFormDesigner.DeleteWidgets;
var
  n: integer;
  cd: TWidgetDesigner;
begin
  n := 0;
  while n < FWidgets.Count do
  begin
    cd := TWidgetDesigner(FWidgets.Items[n]);
    if cd.Selected then
    begin
      cd.Widget.Free;
      cd.Free;
      FWidgets.Delete(n);
    end
    else
      Inc(n);
  end;
  UpdatePropWin;
end;


procedure TFormDesigner.EditWidgetOrder;
var
  frm: TWidgetOrderForm;
  n, fi: integer;
  cd: TWidgetDesigner;
  identlevel: integer;

  procedure AddChildWidgets(pwg: TfpgWidget; slist: TStrings);
  var
    f: integer;
    fcd: TWidgetDesigner;
  begin
    for f := 0 to FWidgets.Count - 1 do
    begin
      fcd := TWidgetDesigner(FWidgets.Items[f]);

      if fcd.Widget.Parent = pwg then
      begin
        frm.list.Items.AddObject(StringOfChar(' ', identlevel) + fcd.Widget.Name + ' : ' + fcd.Widget.ClassName, fcd);
        Inc(identlevel);
        AddChildWidgets(fcd.Widget, slist);
        Dec(identlevel);
      end;

      if fcd.Selected then
        fi := f + 1;
    end;
  end;

begin
  frm := TWidgetOrderForm.Create(nil);
  fi  := 1;

  identlevel := 0;

  AddChildWidgets(FForm, frm.list.Items);

  if fi <= frm.list.ItemCount then
    frm.list.FocusItem := fi;

  if frm.ShowModal = 1 then
  begin
    for n := 0 to FWidgets.Count - 1 do
      TWidgetDesigner(FWidgets.Items[n]).Widget.Visible := False;

    for n := 0 to FWidgets.Count - 1 do
      FWidgets.Items[n] := frm.List.Items.Objects[n];

    for n := 0 to FWidgets.Count - 1 do
    begin
      cd := TWidgetDesigner(FWidgets.Items[n]);
      cd.Widget.Visible := True;
    end;

    for n := 0 to FWidgets.Count - 1 do
    begin
      cd := TWidgetDesigner(FWidgets.Items[n]);
      if cd.Selected then
      begin
        // re-creating the resizers
        cd.Selected := False;
        cd.Selected := True;
      end;
    end;

  end;
  frm.Free;
end;

procedure TFormDesigner.EditTabOrder;
const
  cDivider = ' : ';
var
  frm: TWidgetOrderForm;
  n, fi, i: integer;
  cd: TWidgetDesigner;
  identlevel: integer;
  s: string;
  taborder: integer;

  procedure AddChildWidgets(pwg: TfpgWidget; slist: TStrings);
  var
    f: integer;
    fcd: TWidgetDesigner;
  begin
    for f := 0 to FWidgets.Count - 1 do
    begin
      fcd := TWidgetDesigner(FWidgets.Items[f]);

      if fcd.Widget.Parent = pwg then
      begin
        frm.list.Items.AddObject(StringOfChar(' ', identlevel) + fcd.Widget.Name + cDivider + fcd.Widget.ClassName, fcd);
        Inc(identlevel, 2);
        AddChildWidgets(fcd.Widget, slist);
        Dec(identlevel, 2);
      end;

      if fcd.Selected then
        fi := f + 1;
    end;
  end;

begin
  frm := TWidgetOrderForm.Create(nil);
  frm.WindowTitle := 'Tab Order';
  fi  := 1;
  identlevel := 0;

  AddChildWidgets(FForm, frm.list.Items);

  if fi <= frm.list.ItemCount then
    frm.list.FocusItem := fi;

  if frm.ShowModal = 1 then
  begin
    taborder := 1;
    for n := 0 to frm.List.Items.Count - 1 do
    begin
        try
          if IsPublishedProp(TWidgetDesigner(frm.List.Items.Objects[n]).Widget, 'TabOrder') then
          begin
//            SetPropValue(TWidgetDesigner(frm.List.Items.Objects[n]).Widget, 'TabOrder', taborder);
            TWidgetDesigner(frm.List.Items.Objects[n]).Widget.TabOrder := taborder;
            inc(taborder);
          end;
        except
          // do nothing. TabOrder was not published
        end;
    end;
  end;  { if }
  frm.Free;
end;

procedure TFormDesigner.DesignerKeyPress(var keycode: word; var shiftstate: TShiftState; var consumed: boolean);
var
  dx,
  dy: integer;
begin
  dx       := 0;
  dy       := 0;
  consumed := True;

  case keycode of
    keyLeft:    dx := -1;
    keyRight:   dx := +1;
    keyUp:      dy := -1;
    keyDown:    dy := +1;

    keyDelete: DeleteWidgets;

    keyTab:
        begin
          if ssShift in shiftstate then
            SelectNextWidget(False) // tab backwards
          else
            SelectNextWidget(True); // tab forward
        end;

    keyF1: ShowMessage('ENTER, F11: switch to Properties' + LineEnding +
        'TAB, SHIFT+TAB: select next widget' + LineEnding +
        'F2: edit widget order' + LineEnding +
        'F4: edit items' + LineEnding
        , 'Small help');

    keyF2: EditWidgetOrder;

    //KEY_F4: if PropertyForm.btnEdit.Visible then PropertyForm.btnEdit.Click;

    keyF11,
    keyEnter:
      frmProperties.SetFocus;
//      GfxActivateWindow(frmProperties.WinHandle);
    else
      consumed := False;
  end;

  if (dx <> 0) or (dy <> 0) then
    if (ssShift in shiftstate) then
      MoveResizeWidgets(0, 0, dx, dy)
    else
      MoveResizeWidgets(dx, dy, 0, 0);
end;

(*
procedure TFormDesigner.PutControlByName(x, y: integer; cname: string);
var
  wg: TfpgWidget;
  wgd: TWidgetDesigner;
  wgcname: string;
  newname: string;
  cfrm: TInsertCustomForm;
begin
  wgcname := UpperCase(cname);

  Writeln('Putting control: ', wgcname);

  wg      := nil;
  newname := 'Widget';
  if wgcname = 'LABEL' then
  begin
    newname := GenerateNewName('lbLabel');
    wg      := CreateLabel(FForm, x, y, newname);
  end
  else if wgcname = 'EDIT' then
  begin
    newname := GenerateNewName('edEdit');
    wg      := CreateEdit(FForm, x, y, 150, 0);
    TfpgEdit(wg).Text := newname;
  end
  else if wgcname = 'BUTTON' then
  begin
    newname := GenerateNewName('btnButton');
    wg      := CreateButton(FForm, x, y, 105, newname, nil);
  end
  else if wgcname = 'CHECKBOX' then
  begin
    newname := GenerateNewName('cbCheck');
    wg      := CreateCheckBox(FForm, x, y, newname);
  end
  else if wgcname = 'MEMO' then
  begin
    newname := GenerateNewName('edMemo');
    wg      := TfpgMemo.Create(FForm);
    wg.SetPosition(x, y, 120, 80);
    TfpgMemo(wg).Text := newname;
  end
  else if wgcname = 'TEXTLISTBOX' then
  begin
    newname := GenerateNewName('lstList');
    wg      := TfpgListBox.Create(FForm);
    wg.SetPosition(x, y, 160, 200);
    TfpgListBox(wg).Items.Add(newname);
  end
  else if wgcname = 'COMBOBOX' then
  begin
    newname := GenerateNewName('cbComboBox');
    wg      := CreateComboBox(FForm, x, y, 150, nil);
    TfpgComboBox(wg).Items.Add(newname);
  end
  else
  begin
    // custom component
    cfrm := TInsertCustomForm.Create(nil);
    if cfrm.ShowModal = 1 then
    begin
      newname := cfrm.edName.Text;
      if newname = '' then
        newname := GenerateNewName(cfrm.edClass.Text);
      wg := TOtherWidget.Create(FForm);
      TOtherWidget(wg).wgClassName := cfrm.edClass.Text;
      wg.SetPosition(x, y, 200, 24);
    end;
    cfrm.Free;

  end;

  if wg <> nil then
  begin
    wg.Name     := newname;
    wgd         := AddWidget(wg, nil);
    wg.Visible  := True;
    DeSelectAll;
    wgd.Selected := True;
    UpdatePropWin;
  end;
end;
*)

procedure TFormDesigner.OnPaletteChange(Sender: TObject);
begin
  if PaletteForm.clist.FocusItem > 1 then
    FForm.MouseCursor := mcCross
  else
    FForm.MouseCursor := mcDefault;
end;

procedure TFormDesigner.UpdatePropWin;
var
  n, i: integer;
  cd, scd: TWidgetDesigner;
  wg: TfpgWidget;

  wgcnt: integer;
  //btxt  : boolean;
  //bedit : boolean;

  lastpropname: string;

  wgc: TVFDWidgetClass;
begin
  wgcnt := 0;
  wg    := FForm;
  wgc   := VFDFormWidget;
  scd   := nil;
  for n := 0 to FWidgets.Count - 1 do
  begin
    cd := TWidgetDesigner(FWidgets.Items[n]);
    if cd.Selected then
    begin
      Inc(wgcnt);
      if wgcnt < 2 then
      begin
        wg  := cd.Widget;
        scd := cd;
      end;
    end;
  end;

  if scd <> nil then
    wgc := scd.FVFDClass;

  n := frmProperties.lstProps.FocusItem;
  if (n > 0) and (PropList.GetItem(n) <> nil) then
    lastpropname := PropList.GetItem(n).Name
  else
    lastpropname := '';

  i := 0;

  if PropList.Widget <> wg then
  begin
    frmProperties.lstProps.ReleaseEditor;
    PropList.Clear;
    for n := 1 to wgc.PropertyCount do
    begin
      PropList.AddItem(wgc.GetProperty(n));
      if UpperCase(wgc.GetProperty(n).Name) = UpperCase(lastPropName) then
        i := n;
    end;
    PropList.Widget := wg;
    frmProperties.lstProps.Update;
    if i > 0 then
      frmProperties.lstProps.FocusItem := i;
  end;

  with frmProperties do
  begin
    if wg is TOtherWidget then
      lbClass.Text := TOtherWidget(wg).wgClassName
    else
      lbClass.Text := wg.ClassName;
    edName.Text := wg.Name;

    if scd <> nil then
      edOther.Text := scd.other.Text
    else
      edOther.Text := FFormOther;

    edName.Visible  := (wgcnt < 2);
    edOther.Visible := (wgcnt < 2);

    lstProps.Update;
  end;

  with frmProperties do
  begin
    btnLeft.Text    := IntToStr(wg.Left);
    btnTop.Text     := IntToStr(wg.Top);
    btnWidth.Text   := IntToStr(wg.Width);
    btnHeight.Text  := IntToStr(wg.Height);

    btnAnLeft.Down   := anLeft in wg.Anchors;
    btnAnTop.Down    := anTop in wg.Anchors;
    btnAnRight.Down  := anRight in wg.Anchors;
    btnAnBottom.Down := anBottom in wg.Anchors;
  end;

  Exit;
  {
  with PropertyForm do
  begin
    if wg is TOtherWidget then lbClass.Text8 := TOtherWidget(wg).wgClassName
                          else lbClass.Text8 := wg.ClassName;

    edName.Text8 := wg.Name;

    lbLeft.Text8 := IntToStr(wg.Left);
    lbTop.Text8 := IntToStr(wg.Top);
    lbWidth.Text8 := IntToStr(wg.Width);
    lbHeight.Text8 := IntToStr(wg.Height);

    cbAL.Checked := anLeft in wg.Anchors;
    cbAT.Checked := anTop in wg.Anchors;
    cbAR.Checked := anRight in wg.Anchors;
    cbAB.Checked := anBottom in wg.Anchors;

    btxt  := true;
    bedit := false;
    lbText.Text := u8('Text:');

    if wg is TGfxForm then edText.Text := TGfxForm(wg).WindowTitle
    else if wg is TwgLabel then edText.Text := TwgLabel(wg).Text
    else if wg is TwgEdit  then edText.Text := TwgEdit(wg).Text
    else if wg is TwgButton then edText.Text := TwgButton(wg).Text
    else if wg is TwgCheckBox then edText.Text := TwgCheckBox(wg).Text
    else btxt := false;

    if not btxt and ((wg is TwgMemo) or (wg is TwgChoiceList) or (wg is TwgTextListBox))
    then
    begin
      bedit := true;
      lbText.Text := u8('Items:');
      btnEdit.Text := u8('Edit items...');
    end
    else if (wg is TwgDBGrid) then
    begin
      bedit := true;
      //lbText.Text := u8('Items:');
      btnEdit.Text := u8('Edit columns...');
    end;

    if scd <> nil then
    begin
      edOther.Text := str8to16(scd.other.Text);
    end
    else
    begin
      edOther.Text := str8to16(FFormOther);
    end;

    edText.Visible := btxt;
    lbText.Visible := btxt;
    btnEdit.Visible := bedit;
    edName.Visible := (wgcnt < 2);
    edOther.Visible := (wgcnt < 2);

  end; // with PropertyForm
}
end;

procedure TFormDesigner.OnPropTextChange(Sender: TObject);
{
var
  n : integer;
  cd : TWidgetDesigner;
  wg : TWidget;
  s : string16;
}
begin
  {
  s := PropertyForm.edText.Text;
  wg := nil;
  for n:=0 to FWidgets.Count-1 do
  begin
    cd := TWidgetDesigner(FWidgets.Items[n]);
    if cd.Selected then
    begin
      wg := cd.Widget;
      SetWidgetText(wg,s);
      if wg is TwgLabel then
      with TwgLabel(wg) do
      begin
        if Font.TextWidth16(Text) > width then
        begin
          Width := Font.TextWidth16(Text);
          UpdateWindowPosition;
          cd.UpdateResizerPositions;
        end;
      end;
    end;
  end;

  if wg = nil then
  begin
    FForm.WindowTitle := s;
  end;
}
end;

procedure TFormDesigner.OnPropNameChange(Sender: TObject);
var
  n: integer;
  cd: TWidgetDesigner;
  wg: TfpgWidget;
  s: string;
begin
  //  writeln('namechange');
  s := frmProperties.edName.Text;
  wg := nil;
  for n := 0 to FWidgets.Count - 1 do
  begin
    cd := TWidgetDesigner(FWidgets.Items[n]);
    if cd.Selected then
      wg := cd.Widget;
{
      if GetWidgetText(wg,s) and (wg.Name = str16to8(s)) then
      begin
        PropertyForm.edText.Text8 := s8;
        OnPropTextChange(sender);
      end;
}
  end;

  if wg = nil then
    wg := FForm{
    if FForm.Name = FForm.WindowTitle8 then
    begin
      FForm.WindowTitle8 := s8;
      PropertyForm.edText.Text8 := s8;
    end;
};

  try
    wg.Name := s;
  except
    // invalid name...
  end;
end;

procedure TFormDesigner.OnPropPosEdit(Sender: TObject);
var
  frm: TEditPositionForm;
  btn: TfpgButton;
  ax,
  ay: TfpgCoord;
  wg: TfpgWidget;
  n: integer;
  cd: TWidgetDesigner;
  posval: integer;
  pt: TPoint;

  procedure SetNewPos(awg: TfpgWidget; pval: integer);
  begin
    if Sender = frmProperties.btnLeft then
      awg.Left   := pval
    else if Sender = frmProperties.btnTop then
      awg.Top    := pval
    else if Sender = frmProperties.btnWidth then
      awg.Width  := pval
    else if Sender = frmProperties.btnHeight then
      awg.Height := pval;
  end;

begin
  wg := nil;
  for n := 0 to FWidgets.Count - 1 do
  begin
    cd := TWidgetDesigner(FWidgets.Items[n]);
    if cd.Selected then
    begin
      wg := cd.Widget;
      break;
    end;
  end;

  if wg = nil then
    wg := Form;

  btn      := TfpgButton(Sender);
  frm      := TEditPositionForm.Create(nil);
  btn.WindowToScreen(btn, pt);
//  GfxGetAbsolutePosition(btn.WinHandle, btn.Width, 0, ax, ay);
  ax := pt.X;
  ay := pt.Y;
  frm.Left := ax;
  frm.Top  := ay;
  if Sender = frmProperties.btnLeft then
  begin
    frm.lbPos.Text := 'Left:';
    frm.edPos.Text := IntToStr(wg.Left);
  end
  else if Sender = frmProperties.btnTop then
  begin
    frm.lbPos.Text := 'Top:';
    frm.edPos.Text := IntToStr(wg.Top);
  end
  else if Sender = frmProperties.btnWidth then
  begin
    frm.lbPos.Text := 'Width:';
    frm.edPos.Text := IntToStr(wg.Width);
  end
  else if Sender = frmProperties.btnHeight then
  begin
    frm.lbPos.Text := 'Height:';
    frm.edPos.Text := IntToStr(wg.Height);
  end;

  posval := -9999;
  if frm.ShowModal = 1 then
    posval := StrToIntDef(frm.edPos.Text, -9999);
  frm.Free;

  if posval > -999 then
  begin
    wg := nil;
    for n := 0 to FWidgets.Count - 1 do
    begin
      cd := TWidgetDesigner(FWidgets.Items[n]);
      if cd.Selected then
      begin
        wg := cd.Widget;
        SetNewPos(wg, posval);
        wg.UpdateWindowPosition;
        cd.UpdateResizerPositions;
      end;
    end;

    if wg = nil then
    begin
      SetNewPos(FForm, posval);
      FForm.UpdateWindowPosition;
    end;

  end;

  UpdatePropWin;
end;

procedure TFormDesigner.OnOtherChange(Sender: TObject);
var
  n: integer;
  cd: TWidgetDesigner;
  s: string;
  sc: integer;
begin
  sc := 0;
  s  := frmProperties.edOther.Text;
  for n := 0 to FWidgets.Count - 1 do
  begin
    cd := TWidgetDesigner(FWidgets.Items[n]);
    if cd.Selected then
    begin
      cd.other.Text := s;
      Inc(sc);
    end;
  end;

  if sc < 1 then
    FFormOther := s;
end;

procedure TFormDesigner.OnAnchorChange(Sender: TObject);
var
  n: integer;
  cd: TWidgetDesigner;
  wg: TfpgWidget;
begin
  for n := 0 to FWidgets.Count - 1 do
  begin
    cd := TWidgetDesigner(FWidgets.Items[n]);
    if cd.Selected then
    begin
      wg := cd.Widget;

      wg.Anchors := [];
      if frmProperties.btnAnLeft.Down then
        wg.Anchors := wg.Anchors + [anLeft];
      if frmProperties.btnAnTop.Down then
        wg.Anchors := wg.Anchors + [anTop];
      if frmProperties.btnAnRight.Down then
        wg.Anchors := wg.Anchors + [anRight];
      if frmProperties.btnAnBottom.Down then
        wg.Anchors := wg.Anchors + [anBottom];
    end;
  end;
end;

function TFormDesigner.GenerateNewName(namebase: string): string;
var
  nind, n: integer;
  cd: TWidgetDesigner;
  newname: string;
  bok: boolean;
begin
  nind := 1;
  repeat
    newname := namebase + IntToStr(nind);
    bok := True;
    for n := 0 to FWidgets.Count - 1 do
    begin
      cd := TWidgetDesigner(FWidgets.Items[n]);
      if cd.Widget.Name = newname then
      begin
        bok := False;
        break;
      end;
    end;
    Inc(nind);
  until bok;
  Result := newname;
end;


procedure TFormDesigner.MsgActivate(var msg: TfpgMessageRec);
begin
  msg.Stop := True;
  maindsgn.SelectForm(self);
end;

function TFormDesigner.GetFormSourceDecl: string;
var
  n: integer;
  wd: TWidgetDesigner;
  wgclass: string;
begin
  Result := '';
  for n := 0 to FWidgets.Count - 1 do
  begin
    wd := TWidgetDesigner(FWidgets.Items[n]);
    if wd.Widget is TOtherWidget then
      wgclass := TOtherWidget(wd.Widget).wgClassName
    else
      wgclass := wd.Widget.ClassName;
    Result := Result + '    ' + wd.Widget.Name + ': ' + wgclass + ';' + LineEnding;
  end;
end;

function TFormDesigner.GetFormSourceImpl: string;
var
  s: string;
  sl: TStringList;
  n: integer;
  wd: TWidgetDesigner;
  wg: TfpgWidget;
  wgclass, pwgname: string;
begin
  s := '';

  if maindsgn.SaveComponentNames then
    s := s + '  Name := ' + QuotedStr(FForm.Name) + ';' + LineEnding;

  s := s + '  SetPosition('
      + IntToStr(FForm.Left) + ', '
      + IntToStr(FForm.Top) + ', '
      + IntToStr(FForm.Width) + ', '
      + IntToStr(FForm.Height) + ');' + LineEnding;

{
  // Extend this and the Form Parser to handle WindowPosition, Width and Height
  case FForm.WindowPosition of
    wpUser:
        begin
          s := s + '  SetPosition('
              + IntToStr(FForm.Left) + ', '
              + IntToStr(FForm.Top) + ', '
              + IntToStr(FForm.Width) + ', '
              + IntToStr(FForm.Height) + ');' + LineEnding;
        end;
    else
        begin
          s := s + 'WindowPosition := wpScreenCenter;' + LineEnding;
          s := s + 'Width := ' + IntToStr(FForm.Width) + ';' + LineEnding
              + 'Height := ' + IntToStr(FForm.Height) + ';' + LineEnding;
        end;
  end;
}
  s := s + '  WindowTitle := ' + QuotedStr(FForm.WindowTitle) + ';' + LineEnding;

  //adding other form properties, idented
  sl      := TStringList.Create;
  sl.Text := FFormOther;
  for n := 0 to sl.Count - 1 do
    s := s + '  ' + sl.Strings[n] + LineEnding;
  sl.Free;

  s := s + LineEnding;

  // FORM WIDGETS

  for n := 0 to FWidgets.Count - 1 do
  begin
    wd := TWidgetDesigner(FWidgets.Items[n]);
    wg := wd.Widget;
    if wg.Parent = FForm then
      pwgname := 'self'
    else
      pwgname := wg.Parent.Name;
    if wg is TOtherWidget then
      wgclass := TOtherWidget(wg).wgClassName
    else
      wgclass := wg.ClassName;

    s := s + '  ' + wg.Name + ' := ' + wgclass + '.Create(' + pwgname + ');' + LineEnding +
      '  with ' + wg.Name + ' do' + LineEnding + '  begin' + LineEnding + GetWidgetSourceImpl(wd, '    ') +
      '  end;' + LineEnding + LineEnding;
  end;

  Result := s;
end;

function TFormDesigner.GetWidgetSourceImpl(wd: TWidgetDesigner; ident: string): string;
var
  ts, cs: string;
  s: string;
  wg: TfpgWidget;
  wgc: TVFDWidgetClass;
  n: integer;

  procedure SaveItems(Name: string; sl: TStringList);
  var
    f: integer;
  begin
    for f := 0 to sl.Count - 1 do
      s := s + ident + Name + '.Add(' + QuotedStr(sl.Strings[f]) + ');' + LineEnding;
  end;

  {  procedure SaveColumns(grid : TwgDBGrid);
  var
    f : integer;
    c : TDBColumn;
    alstr : string;
  begin
    for f := 0 to grid.ColumnCount - 1 do
    begin
      c := grid.Columns[f];
      case c.Alignment of
      alRight  : alstr := 'alRight';
      alCenter : alstr := 'alCenter';
      else
        alstr := 'alLeft';
      end;
      s := s + ident + 'AddColumn8('+QuotedStr(u16u8safe(c.Title))+','+QuotedStr(c.FieldName8)
                +','+IntToStr(c.Width)+','+alstr+');'#10;
    end;
  end;
}
begin
  wg  := wd.Widget;
  wgc := wd.FVFDClass;
  s   := '';

  if maindsgn.SaveComponentNames then
    s := s + ident + 'Name := ' + QuotedStr(wg.Name) + ';' + LineEnding;

  s := s + ident + 'SetPosition('
      + IntToStr(wg.Left) + ', '
      + IntToStr(wg.Top) + ', '
      + IntToStr(wg.Width) + ', '
      + IntToStr(wg.Height) + ');' + LineEnding;

  if wg.Anchors <> [anLeft, anTop] then
  begin
    ts := '[';
    cs := '';
    if anLeft in wg.Anchors then
    begin
      ts := ts + cs + 'anLeft';
      cs := ',';
    end;
    if anRight in wg.Anchors then
    begin
      ts := ts + cs + 'anRight';
      cs := ',';
    end;
    if anTop in wg.Anchors then
    begin
      ts := ts + cs + 'anTop';
      cs := ',';
    end;
    if anBottom in wg.Anchors then
    begin
      ts := ts + cs + 'anBottom';
      cs := ',';
    end;
    ts := ts + '];';
    s := s + ident + 'Anchors := ' + ts + LineEnding;
  end;

  for n := 1 to wgc.PropertyCount do
    s := s + wgc.GetProperty(n).GetPropertySource(wg, ident);

  {
  if wg is TwgMemo then
  begin
    SaveItems('Lines',TwgMemo(wg).Lines);
  end
  else if wg is TwgChoiceList then
  begin
    SaveItems('Items',TwgChoiceList(wg).Items);
  end
  else if wg is TwgTextListBox then
  begin
    SaveItems('Items',TwgTextListBox(wg).Items);
  end
  else if wg is TwgDBGrid then
  begin
    SaveColumns(TwgDBGrid(wg));
  end
  else
    if GetWidgetText(wg, ts) then
    begin
      s := s + ident + 'Text := u8('+QuotedStr(u8encode(ts))+');'#10;  // encoding with all printable characters
    end;
}

  for n := 0 to wd.other.Count - 1 do
    if trim(wd.other.Strings[n]) <> '' then
      s := s + ident + wd.other.Strings[n] + LineEnding;

  Result := s;
end;

procedure TFormDesigner.OnEditWidget(Sender: TObject);
var
  n: integer;
  cd: TWidgetDesigner;
  wg: TfpgWidget;
begin
  for n := 0 to FWidgets.Count - 1 do
  begin
    cd := TWidgetDesigner(FWidgets.Items[n]);
    if cd.Selected then
    begin
      wg := cd.Widget;

      // Running widget editor;
      RunWidgetEditor(cd, wg);

      Exit;
    end;
  end;
end;

procedure EditItems(sl: TStringList);
var
  frmie: TItemEditorForm;
  //ax,ay : integer;
begin
  frmie := TItemEditorForm.Create(nil);
  //GfxGetAbsolutePosition(PropertyForm.btnEdit.WinHandle, PropertyForm.btnEdit.width, 0, ax,ay);
  //frmie.Left := ax;
  //frmie.Top := ay;

  frmie.edItems.Lines.Assign(sl);
  if frmie.ShowModal = 1 then
  begin
//    Writeln('OK');
    sl.Assign(frmie.edItems.Lines);
  end;
  frmie.Free;
end;

procedure TFormDesigner.RunWidgetEditor(wgd: TWidgetDesigner; wg: TfpgWidget);
begin
  if wg is TfpgMemo then
  begin
    EditItems(TfpgMemo(wg).Lines);
    wg.Invalidate;
  end
  else if wg is TfpgComboBox then
  begin
    EditItems(TfpgComboBox(wg).Items);
    wg.Invalidate;
  end
  else if wg is TfpgListBox then
  begin
    EditItems(TfpgListBox(wg).Items);
    wg.Invalidate;
  end;
end;

procedure TFormDesigner.InsertWidget(pwg: TfpgWidget; x, y: integer; wgc: TVFDWidgetClass);
var
  cfrm: TInsertCustomForm;
  newname, newclassname: string;
  wg: TfpgWidget;
  wgd: TWidgetDesigner;
begin
//  writeln('TFormDesigner.InsertWidget');
  if wgc = nil then
    Exit;

  newname := '';

  if wgc.WidgetClass = TOtherWidget then
  begin
    newclassname := '';
    cfrm         := TInsertCustomForm.Create(nil);
    cfrm.edName.Text := GenerateNewName(wgc.NameBase);
    cfrm.edClass.Text := 'Tfpg';
    if cfrm.ShowModal = 1 then
    begin
      newname      := cfrm.edName.Text;
      newClassName := cfrm.edClass.Text;
    end;
    cfrm.Free;
    if (newname = '') or (newclassname = '') then
      Exit;
  end;

  wg := wgc.CreateWidget(pwg);
  if wg <> nil then
  begin
    wg.FormDesigner := self;
    if newname = '' then
      newname := GenerateNewName(wgc.NameBase);
    wg.Name := newname;
    if wgc.WidgetClass = TOtherWidget then
      TOtherWidget(wg).wgClassName := newclassname;
    wgd          := AddWidget(wg, wgc);
    wg.Visible   := True;
    wg.SetPosition(x, y, wg.Width, wg.Height);
    DeSelectAll;
    wgd.Selected := True;
    UpdatePropWin;
  end;
end;

function TFormDesigner.FindWidgetByName(const wgname: string): TfpgWidget;
var
  n: integer;
  wgnameuc: string;
  cd: TWidgetDesigner;
begin
  wgnameuc := UpperCase(wgname);
  Result   := nil;
  for n := 0 to FWidgets.Count - 1 do
  begin
    cd := TWidgetDesigner(FWidgets.Items[n]);
    if UpperCase(cd.Widget.Name) = wgnameuc then
    begin
      Result := cd.Widget;
      Exit;
    end;
  end;
end;

{ TDesignedForm }

procedure TDesignedForm.AfterCreate;
begin
  inherited AfterCreate;
  WindowPosition := wpUser;
  WindowTitle := 'New Form';
  SetPosition(300, 150, 300, 250);
//  TComponentFriendClass(self).SetDesigning(True);
end;


{ TOtherWidget }

procedure TOtherWidget.HandlePaint;
var
  s: string;
begin
  Canvas.BeginDraw;
  inherited HandlePaint;

  Canvas.Clear(FBackgroundColor);
  Canvas.SetFont(FFont);
  Canvas.SetColor(clWidgetFrame);
  Canvas.DrawRectangle(0, 0, Width, Height);
  Canvas.SetTextColor(clText1);
  s := Name + ': ' + wgClassName;
  Canvas.DrawString(2, 2, s);
  
  Canvas.EndDraw;
end;

constructor TOtherWidget.Create(AOwner: TComponent);
begin
  inherited;
  wgClassName := 'TfpgWidget';
  FBackgroundColor := $C0E0C0;
  FFont   := fpgStyle.DefaultFont;
  FWidth  := 120;
  FHeight := 32;
end;

end.

