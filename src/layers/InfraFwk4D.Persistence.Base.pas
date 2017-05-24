unit InfraFwk4D.Persistence.Base;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Rtti,
  System.Generics.Collections,
  Data.DB,
  Data.DBCommon,
  InfraFwk4D.Persistence,
  InfraFwk4D.DataSet.Iterator,
  SQLBuilder4D,
  SQLBuilder4D.Parser,
  SQLBuilder4D.Parser.GaSQLParser;

type

  TDriverAdapterBase = class(TInterfacedObject)
  private
    { private declarations }
  protected
    { protected declarations }
  public
    { public declarations }
  end;

  TDriverConnectionAdapter<T: TCustomConnection> = class(TDriverAdapterBase, IDBConnection<T>)
  private
    fComponent: T;
  protected
    function GetComponent: T;
  public
    constructor Create(const component: T);
  end;

  TDriverStatementAdapter<T: TCustomConnection> = class(TDriverAdapterBase, IDBStatement)
  private
    fConnection: IDBConnection<T>;
    fQuery: string;
    fParams: TDictionary<string, TValue>;
    fPreparedDataSet: TDataSet;
  protected
    function GetQuery: string;
    function GetConnection: IDBConnection<T>;
    function GetParams: TDictionary<string, TValue>;
    function GetPreparedDataSet: TDataSet;
    procedure SetPreparedDataSet(const value: TDataSet);

    procedure DataSetPreparation(const dataSet: TDataSet); virtual; abstract;

    function Build(const query: string): IDBStatement; overload;
    function Build(const query: ISQL): IDBStatement; overload;

    function AddOrSetParam(const name: string; const value: TValue): IDBStatement; overload;
    function AddOrSetParam(const name: string; const value: ISQLValue): IDBStatement; overload;
    function ClearParams: IDBStatement;
    function Prepare(const dataSet: TDataSet): IDBStatement;

    procedure Open(const dataSet: TDataSet); overload;
    procedure Open(const iterator: IDataSetIterator); overload;

    procedure Execute; overload;
    procedure Execute(const commit: Boolean); overload; virtual; abstract;

    function AsDataSet: TDataSet; overload;
    function AsDataSet(const fetchRows: Integer): TDataSet; overload; virtual; abstract;

    function AsIterator: IDataSetIterator; overload;
    function AsIterator(const fetchRows: Integer): IDataSetIterator; overload;

    function AsField: TField;
  public
    constructor Create(const connection: IDBConnection<T>);
    destructor Destroy; override;
  end;

  TDriverSessionAdapter<T: TCustomConnection> = class(TDriverAdapterBase, IDBSession<T>)
  private
    fConnection: IDBConnection<T>;
  protected
    function GetConnection: IDBConnection<T>;
    function NewStatement: IDBStatement; virtual; abstract;
  public
    constructor Create(const connection: IDBConnection<T>);
  end;

  TDriverQueryChangerAdapter<T: TDataSet> = class(TDriverAdapterBase, IDBQueryChanger)
  private
    fDataSet: T;
    fParser: ISQLParserSelect;
    fQuery: string;
    function ConditionIs(const condition: string; const token: TSQLToken): Boolean;
  protected
    function IsOrderBy(const condition: string): Boolean;
    function IsHaving(const condition: string): Boolean;
    function IsGroupBy(const condition: string): Boolean;
    function IsWhere(const condition: string): Boolean;

    function GetParser: ISQLParserSelect;
    function GetDataSet: T;

    function GetDataSetQueryText: string; virtual; abstract;
    procedure SetDataSetQueryText(const value: string); virtual; abstract;

    function Initialize(const query: string): IDBQueryChanger; overload;
    function Initialize(const query: ISQL): IDBQueryChanger; overload;

    function Add(const condition: string): IDBQueryChanger; overload;
    function Add(const condition: ISQLClause): IDBQueryChanger; overload;

    function Restore: IDBQueryChanger;

    procedure Activate;
  public
    constructor Create(const dataSet: T);
  end;

  TDriverMetaDataInfoAdapter<T: TCustomConnection> = class(TDriverAdapterBase, IDBMetaDataInfo)
  private
    fSession: IDBSession<T>;
  protected
    function GetSession: IDBSession<T>;

    function GetTables: IDataSetIterator; virtual; abstract;
    function GetFields(const tableName: string): IDataSetIterator; virtual; abstract;
    function GetPrimaryKeys(const tableName: string): IDataSetIterator; virtual; abstract;
    function GetIndexes(const tableName: string): IDataSetIterator; virtual; abstract;
    function GetForeignKeys(const tableName: string): IDataSetIterator; virtual; abstract;
    function GetGenerators: IDataSetIterator; virtual; abstract;

    function TableExists(const tableName: string): Boolean;
    function FieldExists(const tableName, fieldName: string): Boolean;
    function PrimaryKeyExists(const tableName, primaryKeyName: string): Boolean;
    function IndexExists(const tableName, indexName: string): Boolean;
    function ForeignKeyExists(const tableName, foreignKeyName: string): Boolean;
    function GeneratorExists(const generatorName: string): Boolean;
  public
    constructor Create(const session: IDBSession<T>);
  end;

implementation

{ TDriverConnectionAdapter<T> }

constructor TDriverConnectionAdapter<T>.Create(const component: T);
begin
  inherited Create;
  fComponent := component;
end;

function TDriverConnectionAdapter<T>.GetComponent: T;
begin
  if not Assigned(fComponent) then
    raise EPersistenceException.CreateFmt('Connection component with database not defined in %s!', [Self.ClassName]);
  Result := fComponent;
end;

{ TDriverStatementAdapter<T> }

function TDriverStatementAdapter<T>.AsDataSet: TDataSet;
begin
  Result := AsDataSet(0);
end;

function TDriverStatementAdapter<T>.AsField: TField;
var
  it: IDataSetIterator;
begin
  Result := nil;
  it := TDataSetIterator.Create(AsDataSet);
  if not it.IsEmpty then
    Result := it.Fields[0];
end;

function TDriverStatementAdapter<T>.AsIterator(const fetchRows: Integer): IDataSetIterator;
begin
  Result := TDataSetIterator.Create(AsDataSet(fetchRows));
end;

function TDriverStatementAdapter<T>.AsIterator: IDataSetIterator;
begin
  Result := AsIterator(0);
end;

function TDriverStatementAdapter<T>.Build(const query: ISQL): IDBStatement;
begin
  Result := Build(query.ToString);
end;

function TDriverStatementAdapter<T>.Build(const query: string): IDBStatement;
begin
  fQuery := query;
  Result := Self;
end;

function TDriverStatementAdapter<T>.ClearParams: IDBStatement;
begin
  fParams.Clear;
  Result := Self;
end;

constructor TDriverStatementAdapter<T>.Create(const connection: IDBConnection<T>);
begin
  inherited Create;
  fConnection := connection;
  fQuery := EmptyStr;
  fParams := TDictionary<string, TValue>.Create;
  SetPreparedDataSet(nil);
end;

destructor TDriverStatementAdapter<T>.Destroy;
begin
  fParams.Free;
  inherited Destroy;
end;

procedure TDriverStatementAdapter<T>.Execute;
begin
  Execute(False);
end;

procedure TDriverStatementAdapter<T>.Open(const iterator: IDataSetIterator);
begin
  Open(iterator.GetDataSet);
end;

function TDriverStatementAdapter<T>.Prepare(const dataSet: TDataSet): IDBStatement;
begin
  SetPreparedDataSet(dataSet);
  Result := Self;
end;

procedure TDriverStatementAdapter<T>.SetPreparedDataSet(const value: TDataSet);
begin
  fPreparedDataSet := value;
end;

function TDriverStatementAdapter<T>.GetConnection: IDBConnection<T>;
begin
  if not Assigned(fConnection) then
    raise EPersistenceException.CreateFmt('Connection not defined in %s!', [Self.ClassName]);
  Result := fConnection;
end;

function TDriverStatementAdapter<T>.GetParams: TDictionary<string, TValue>;
begin
  Result := fParams;
end;

function TDriverStatementAdapter<T>.GetPreparedDataSet: TDataSet;
begin
  Result := fPreparedDataSet;
end;

function TDriverStatementAdapter<T>.GetQuery: string;
begin
  Result := fQuery;
end;

procedure TDriverStatementAdapter<T>.Open(const dataSet: TDataSet);
begin
  DataSetPreparation(dataSet);
  dataSet.Open;
end;

function TDriverStatementAdapter<T>.AddOrSetParam(const name: string; const value: TValue): IDBStatement;
begin
  fParams.AddOrSetValue(name, value);
  Result := Self;
end;

function TDriverStatementAdapter<T>.AddOrSetParam(const name: string; const value: ISQLValue): IDBStatement;
begin
  Result := AddOrSetParam(name, value.ToString);
end;

{ TDriverSessionAdapter<T> }

function TDriverSessionAdapter<T>.GetConnection: IDBConnection<T>;
begin
  if not Assigned(fConnection) then
    raise EPersistenceException.CreateFmt('Connection not defined in %s!', [Self.ClassName]);
  Result := fConnection;
end;

constructor TDriverSessionAdapter<T>.Create(const connection: IDBConnection<T>);
begin
  inherited Create;
  fConnection := connection;
end;

{ TDriverQueryChangerAdapter<T> }

procedure TDriverQueryChangerAdapter<T>.Activate;
begin
  fDataSet.Open;
  fParser.Parse(fQuery);
end;

function TDriverQueryChangerAdapter<T>.Add(const condition: ISQLClause): IDBQueryChanger;
begin
  Result := Add(condition.ToString);
end;

function TDriverQueryChangerAdapter<T>.Add(const condition: string): IDBQueryChanger;
begin
  if IsOrderBy(condition) then
    fParser.AddOrderBy(condition)
  else if IsHaving(condition) then
    fParser.AddHaving(condition)
  else if IsGroupBy(condition) then
    fParser.AddGroupBy(condition)
  else if IsWhere(condition) then
    fParser.AddWhere(condition)
  else
    raise EPersistenceException.CreateFmt('SQL query condition is not valid for %s!', [Self.ClassName]);
  SetDataSetQueryText(fParser.ToString);
  Result := Self;
end;

function TDriverQueryChangerAdapter<T>.ConditionIs(const condition: string; const token: TSQLToken): Boolean;
var
  sqlToken: TSQLToken;
  curSection: TSQLToken;
  start: PWideChar;
  s: string;
  idOption: IDENTIFIEROption;
begin
  Result := False;
  idOption := idMixCase;
  start := PWideChar(condition);
  curSection := stUnknown;
  repeat
    sqlToken := NextSQLTokenEx(start, s, curSection, idOption);
    if (sqlToken = token) then
      Exit(True);
    curSection := sqlToken;
  until sqlToken in [stEnd];
end;

constructor TDriverQueryChangerAdapter<T>.Create(const dataSet: T);
begin
  inherited Create;
  fDataSet := dataSet;
  fParser := TGaSQLParserFactory.Select;
  fQuery := EmptyStr;
  Initialize(GetDataSetQueryText);
end;

function TDriverQueryChangerAdapter<T>.GetDataSet: T;
begin
  Result := fDataSet;
end;

function TDriverQueryChangerAdapter<T>.GetParser: ISQLParserSelect;
begin
  Result := fParser;
end;

function TDriverQueryChangerAdapter<T>.Initialize(const query: string): IDBQueryChanger;
begin
  fDataSet.Close;
  fQuery := query;
  fParser.Parse(fQuery);
  SetDataSetQueryText(fParser.ToString);
  Result := Self;
end;

function TDriverQueryChangerAdapter<T>.Initialize(const query: ISQL): IDBQueryChanger;
begin
  Result := Initialize(query.ToString);
end;

function TDriverQueryChangerAdapter<T>.IsGroupBy(const condition: string): Boolean;
begin
  Result := ConditionIs(condition, stGroupBy);
end;

function TDriverQueryChangerAdapter<T>.IsHaving(const condition: string): Boolean;
begin
  Result := ConditionIs(condition, stHaving);
end;

function TDriverQueryChangerAdapter<T>.IsOrderBy(const condition: string): Boolean;
begin
  Result := ConditionIs(condition, stOrderBy);
end;

function TDriverQueryChangerAdapter<T>.IsWhere(const condition: string): Boolean;
begin
  Result := ConditionIs(condition, stWhere);
end;

function TDriverQueryChangerAdapter<T>.Restore: IDBQueryChanger;
begin
  fDataSet.Close;
  fParser.Parse(fQuery);
  SetDataSetQueryText(fParser.ToString);
  Result := Self;
end;

{ TDriverMetaDataInfoAdapter<T> }

constructor TDriverMetaDataInfoAdapter<T>.Create(const session: IDBSession<T>);
begin
  inherited Create;
  fSession := session;
end;

function TDriverMetaDataInfoAdapter<T>.FieldExists(const tableName, fieldName: string): Boolean;
var
  it: IDataSetIterator;
begin
  Result := False;
  it := GetFields(tableName);
  while it.HasNext do
    if it.FieldByName('COLUMN_NAME').AsString.Equals(fieldName) then
      Exit(True);
end;

function TDriverMetaDataInfoAdapter<T>.ForeignKeyExists(const tableName, foreignKeyName: string): Boolean;
var
  it: IDataSetIterator;
begin
  Result := False;
  it := GetForeignKeys(tableName);
  while it.HasNext do
    if it.FieldByName('FKEY_NAME').AsString.Equals(foreignKeyName) then
      Exit(True);
end;

function TDriverMetaDataInfoAdapter<T>.GeneratorExists(const generatorName: string): Boolean;
var
  it: IDataSetIterator;
begin
  Result := False;
  it := GetGenerators;
  while it.HasNext do
    if it.FieldByName('GENERATOR_NAME').AsString.Equals(generatorName) then
      Exit(True);
end;

function TDriverMetaDataInfoAdapter<T>.GetSession: IDBSession<T>;
begin
  if not Assigned(fSession) then
    raise EPersistenceException.CreateFmt('Session not defined in %s!', [Self.ClassName]);
  Result := fSession;
end;

function TDriverMetaDataInfoAdapter<T>.IndexExists(const tableName, indexName: string): Boolean;
var
  it: IDataSetIterator;
begin
  Result := False;
  it := GetIndexes(tableName);
  while it.HasNext do
    if it.FieldByName('INDEX_NAME').AsString.Equals(indexName) then
      Exit(True);
end;

function TDriverMetaDataInfoAdapter<T>.PrimaryKeyExists(const tableName, primaryKeyName: string): Boolean;
var
  it: IDataSetIterator;
begin
  Result := False;
  it := GetPrimaryKeys(tableName);
  while it.HasNext do
    if it.FieldByName('PKEY_NAME').AsString.Equals(primaryKeyName) then
      Exit(True);
end;

function TDriverMetaDataInfoAdapter<T>.TableExists(const tableName: string): Boolean;
var
  it: IDataSetIterator;
begin
  Result := False;
  it := GetTables;
  while it.HasNext do
    if it.FieldByName('TABLE_NAME').AsString.Equals(tableName) then
      Exit(True);
end;

end.
