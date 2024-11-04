local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local RunService = game:GetService("RunService")

local Reliability = require(ReplicatedFirst.Packages.Reliability)
local Config = require(script.Config)

type RecoveryData = {
    Data: DataStructure;
    DataStore: string;
    Key: string;
}

type RecoveryMessage = {
    Data: RecoveryData
}

type BaseValue<Type> = ValueBase & {
    Value: Type
}

type CacheInstace = {RBXScriptConnection}

export type DataStructure = {[string | number]: any}
type DataStructureMetadata = {
    Session: number?;
    Locked: number;
}

export type DataSessionClass = {
    __index: DataSessionMethods;

    get: (SessionID: number | string, UserIds: {number}? ) -> DataSession
}

export type DataSessionProperties = {
    SessionID: SessionID;
    UserIds: {number};
    Separator: string;

    Recovery: {[string]: thread};

    Replicators: {[string]: RemoteEvent};

    Cache: {[string]: DataStructure};
    DataStores: {[string]: GlobalDataStore};

    Initialized: number;
}

export type DataSessionMethods = {
    Separator: string;

    Load: (self: DataSession, DataStore: string, Key: string, Fallback: DataStructure?, Tries: number?, RetryTime: number?) -> DataStructure?;
    LoadLocal: (self: DataSession, DataStore: string, Key: string, LocalData: DataStructure) -> ();
    
    Update: (self: DataSession, Data: DataStructure, UpdatedData: DataStructure) -> ();

    CreateReplicator: (self: DataSession, Path: string, Replicator: string) -> ();

    Edit: (self: DataSession, Path: string, Value: any) -> ();
    Add: (self: DataSession, Path: string, Value: any) -> ();
    Subtract: (self: DataSession, Path: string, Value: any) -> ();

    Replicate: (self: DataSession, Path: string) -> ();

    Delete: (self: DataSession, Key: string) -> ();
    Save: (self: DataSession, Key: string) -> ();
    Release: (self: DataSession, Key: string) -> ();

    Destroy: (self: DataSession, IgnoreRelease: boolean?) -> ();
}

export type DataSession = typeof(setmetatable({} :: DataSessionProperties, {} :: DataSessionClass))

export type SessionID = string | number

local IS_STUDIO: boolean = RunService:IsStudio()

local SESSION_RECONCILE_THRESHOLD: number = 120

local SESSION_LOCK_EXPIRE: number = Config.SESSION_LOCK_EXPIRE
local SESSION_LOCK_ENABLED: boolean | boolean = IS_STUDIO and Config.STUDIO_SAVE or Config.GAME_SAVE

local CROSS_SERVER_RECOVERY_TIMEOUT: number = Config.CROSS_SERVER_RECOVERY_TIMEOUT

local LOAD_TRY_AMOUNT: number = Config.LOAD_TRY_AMOUNT
local LOAD_RETRY_TIME: number = Config.LOAD_RETRY_TIME

local DataSession: DataSessionMethods = {
    Separator = "."
} :: DataSessionMethods

local DataSessionClass: DataSessionClass = {} :: DataSessionClass
DataSessionClass.__index = DataSession

local Sessions: {[SessionID]: DataSession} = {}
local BudgetWaitlist: {[Enum.DataStoreRequestType]: {thread}} = {}

for _, EnumItem in Enum.DataStoreRequestType:GetEnumItems() do
    BudgetWaitlist[EnumItem] = {}
end

local function DeepCopy(Value: any): any
    if not Value then
        return Value
    end

    if type(Value) == "table" then
        local Copied: { [any]: any } = {}

        for Index, ChildValue in Value do
            Copied[Index] = DeepCopy(ChildValue)
        end

        return Copied
    else
        return Value
    end
end

local function FromPath(Path: string, Data: DataStructure, Separator: string): (DataStructure, string)
    local Nodes: {string} = Path:split(Separator)

    local CurrentPath: DataStructure = Data
    local LastIndex: string = Nodes[#Nodes]

    for _, Index: string in Nodes do
        local NewPath: DataStructure = CurrentPath[Index]
        if type(NewPath) ~= "table" then
            break
        end

        CurrentPath = NewPath
    end

    return CurrentPath, LastIndex
end

local function BudgetScheduler(): ()
    for RequestType: Enum.DataStoreRequestType, Waitlist: {thread} in BudgetWaitlist do
        local WaitingThread: thread? = table.remove(Waitlist,1)
        if DataStoreService:GetRequestBudgetForRequestType(RequestType) > 0 and WaitingThread then
            coroutine.resume(WaitingThread)
        end
    end
end

local function WaitForBudget(RequestType: Enum.DataStoreRequestType): ()
    table.insert(BudgetWaitlist[RequestType], coroutine.running())
    coroutine.yield()
end

function DataSessionClass.get(SessionID: SessionID, UserIds: {number}?): DataSession
    if Sessions[SessionID] then
        return Sessions[SessionID]
    end

    local NewSession: DataSession = setmetatable({
        SessionID = SessionID;

        Recovery = {};

        UserIds = UserIds or {};

        Separator = ".";

        Replicators = {};
        DataStores = {};
        Cache = {};

        Initialized = workspace:GetServerTimeNow();
    }, DataSessionClass)

    MessagingService:SubscribeAsync(SessionID, function(Message: RecoveryMessage): ()
        local Data: RecoveryData = Message.Data

        local RecoveryThread: thread = NewSession.Recovery[Data.DataStore..Data.Key]
        if RecoveryThread then
            coroutine.resume(RecoveryThread, Data.Data)
        end
    end)

    Sessions[SessionID] = NewSession

    return NewSession
end

function DataSession:Load(DataStore: string, Key: string, Fallback: DataStructure?, Tries: number?, RetryTime: number?): DataStructure?
    local GlobalStore: DataStore = DataStoreService:GetDataStore(DataStore, self.SessionID)

    local Success: boolean, Result: string | DataStructure, Attempts: number = false, nil, 0
    local DataInfo: DataStoreKeyInfo
    repeat 
        Attempts += 1

        WaitForBudget(Enum.DataStoreRequestType.GetAsync)

        if not Result then
            Success, Result, DataInfo = pcall(GlobalStore.GetAsync, GlobalStore, Key);
            if Success and Result and DataInfo:GetMetadata().Session then
                if os.time() - DataInfo.UpdatedTime < SESSION_LOCK_EXPIRE and not IS_STUDIO then
                    local Thread: thread = coroutine.running()

                    local RecoveryKey: string = DataStore..Key
                    self.Recovery[RecoveryKey] = Thread

                    MessagingService:PublishAsync(self.SessionID, {DataStore=DataStore; Key=Key})

                    local Timeout: thread = task.delay(CROSS_SERVER_RECOVERY_TIMEOUT, coroutine.resume, Thread, nil)
                    Result = coroutine.yield()

                    self.Recovery[RecoveryKey] = nil
                    pcall(task.cancel, Timeout)

                    Success = Result ~= nil
                end
            elseif Success and not Result then
                Result = DeepCopy(Fallback)
            end
        end

        if Success then
            self:Save(Key)
        end

        task.wait(RetryTime or LOAD_RETRY_TIME)
    until
        Success or Attempts > (Tries or LOAD_TRY_AMOUNT)

    self.DataStores[Key] = GlobalStore
    self.Cache[Key] = Result or DeepCopy(Fallback)
    return Success and (Result :: DataStructure) or nil
end

function DataSession:LoadLocal(DataStore: string, Key: string, LocalData: DataStructure): ()
    if self.Cache[Key] then
        return
    end

    self.DataStores[Key] = DataStoreService:GetDataStore(DataStore, self.SessionID)
    self.Cache[Key] = LocalData
end

function DataSession:CreateReplicator(Path: string, Replicator: string): ()
    if self.Replicators[Path] then
        return
    end

    self.Replicators[Path] = Reliability.getReliable(Replicator)
end

function DataSession:Edit(Path: string, Value: any): ()
    local CurrentPath: DataStructure, LastIndex: string = FromPath(Path, self.Cache, self.Separator or ".")

    if CurrentPath[LastIndex] then
        CurrentPath[LastIndex] = Value
    end

    self:Replicate(Path)
end

function DataSession:Add(Path: string, Value: any): ()
    local CurrentPath: DataStructure, LastIndex: string = FromPath(Path, self.Cache, self.Separator)

    if CurrentPath[LastIndex] then
        CurrentPath[LastIndex] += Value
    end

    self:Replicate(Path)
end

function DataSession:Subtract(Path: string, Value: any): ()
    local CurrentPath: DataStructure, LastIndex: string = FromPath(Path, self.Cache, self.Separator)

    if CurrentPath[LastIndex] then
        CurrentPath[LastIndex] -= Value
    end

    self:Replicate(Path)
end

function DataSession:Replicate(Path: string): ()
    local Replicator: RemoteEvent = self.Replicators[Path]
    if not Replicator then
        return
    end

    local CurrentPath: DataStructure, LastIndex: string = FromPath(Path, self.Cache, self.Separator)
    if not CurrentPath[LastIndex] then
        return
    end

    local Data: any = CurrentPath[LastIndex]

    for _, UserId: number in self.UserIds do
        local Player: Player? = Players:GetPlayerByUserId(UserId)
        if not Player then 
            continue
        end

        Replicator:FireClient(Player, Data)
    end
end

function DataSession:Update(Data: DataStructure, UpdatedData: DataStructure): ()
    for Index: string | number, Value: any in UpdatedData do
        if Data[Index] == nil then
            Data[Index] = DeepCopy(Value)
        end
    end
end

function DataSession:Delete(Key: string): ()
    local Cache: DataStructure = self.Cache[Key]
    local DataStore: GlobalDataStore = self.DataStores[Key]

    if not Cache or not DataStore then
       return
    end

    local Deleted: boolean, Retry: number = false,0

    repeat 
        WaitForBudget(Enum.DataStoreRequestType.RemoveVersionAsync)

        Deleted = pcall(DataStore.RemoveAsync, DataStore, Key)

        if not Deleted then
            task.wait(Retry)
            Retry += 0.5
        end
    until
        Deleted
end

function DataSession:Save(Key: string): ()
    if SESSION_LOCK_ENABLED then
        return
    end

    local Cache: DataStructure = self.Cache[Key]
    local DataStore: GlobalDataStore = self.DataStores[Key]

    if not Cache or not DataStore then
        return
    end

    local SetOptions: DataStoreSetOptions = Instance.new("DataStoreSetOptions")
    SetOptions:SetMetadata({
        Session = game.JobId
    })

    local Saved: boolean, Throw: string? = false, nil;
    repeat 

        WaitForBudget(Enum.DataStoreRequestType.SetIncrementAsync)

        local Error: string;
        Saved, Error = pcall(DataStore.SetAsync, DataStore, Key, Cache, self.UserIds, SetOptions)

        if Error then
            print("Implement error handling later")
        end


    until
        Saved or Throw

    return Throw
end

function DataSession:Release(Key: string): ()
    if SESSION_LOCK_ENABLED then
        return
    end

    local Cache: DataStructure = self.Cache[Key]
    local DataStore: GlobalDataStore = self.DataStores[Key]

    if not Cache or not DataStore then
        return
    end

    local SetOptions: DataStoreSetOptions = Instance.new("DataStoreSetOptions")
    SetOptions:SetMetadata({
        Session = nil;
    })

    local Saved: boolean, Retry: number = false, 0;
    repeat 
        task.wait(Retry)

        WaitForBudget(Enum.DataStoreRequestType.SetIncrementAsync)

        local Error: string;
        Saved, Error = pcall(DataStore.SetAsync, DataStore, Key, Cache, self.UserIds, SetOptions)

        if Error then
            print("Implement error handling later")
        end

        Retry += 5
    until
        Saved or Retry >= 50

    self.Cache[Key] = nil
    task.delay(Saved and 1 or SESSION_RECONCILE_THRESHOLD, DataSession.Destroy, self, true)
end

function DataSession:Destroy(IgnoreRelease: boolean?): ()
    if not IgnoreRelease then
        for Key: string,_ in self.Cache do
            self:Release(Key)
        end
    end

    for _, Replicator: RemoteEvent in self.Replicators do
        Replicator:Destroy()
    end

    Sessions[self.SessionID] = nil
    table.clear(self)
end

RunService.Stepped:Connect(BudgetScheduler)

return DataSessionClass