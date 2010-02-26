{
    fpGUI  -  Free Pascal GUI Toolkit

    Copyright (C) 2006 - 2010 See the file AUTHORS.txt, included in this
    distribution, for details of the copyright.

    See the file COPYING.modifiedLGPL, included in this distribution,
    for details about redistributing fpGUI.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

    Description:
      This unit defines alias types to bind each backend graphics library
      to fpg_main without the need for IFDEF's
}

unit fpg_interface;

{$mode objfpc}{$H+}

interface

uses
  fpg_gdi;

type
  TfpgFontResourceImpl  = TfpgGDIFontResource;
  TfpgImageImpl         = TfpgGDIImage;
  TfpgCanvasImpl        = TfpgGDICanvas;
  TfpgWindowImpl        = TfpgGDIWindow;
  TfpgApplicationImpl   = TfpgGDIApplication;
  TfpgClipboardImpl     = TfpgGDIClipboard;
  TfpgFileListImpl      = TfpgGDIFileList;

implementation

end.

