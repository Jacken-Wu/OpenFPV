using System;
using System.IO;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
namespace OpenFPVBuild {
    // Build-time Windows resources only; no game runtime dependency.
    public static class WindowsIcon {
        delegate bool NameCallback(IntPtr module, IntPtr type, IntPtr name, IntPtr parameter);
        delegate bool LanguageCallback(IntPtr module, IntPtr type, IntPtr name, ushort language, IntPtr parameter);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr LoadLibraryEx(string file, IntPtr reserved, uint flags);
        [DllImport("kernel32.dll")] static extern bool FreeLibrary(IntPtr module);
        [DllImport("kernel32.dll", EntryPoint="EnumResourceNamesW", SetLastError=true)] static extern bool EnumResourceNames(IntPtr module, IntPtr type, NameCallback callback, IntPtr parameter);
        [DllImport("kernel32.dll", EntryPoint="EnumResourceLanguagesW", SetLastError=true)] static extern bool EnumResourceLanguages(IntPtr module, IntPtr type, IntPtr name, LanguageCallback callback, IntPtr parameter);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr BeginUpdateResource(string file, bool deleteExisting);
        [DllImport("kernel32.dll", EntryPoint="UpdateResourceW", SetLastError=true)] static extern bool UpdateResource(IntPtr handle, IntPtr type, IntPtr name, ushort language, byte[] data, uint length);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool EndUpdateResource(IntPtr handle, bool discard);
        [DllImport("kernel32.dll", EntryPoint="FindResourceW", SetLastError=true)] static extern IntPtr FindResource(IntPtr module, IntPtr name, IntPtr type);
        [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr LoadResource(IntPtr module, IntPtr resource);
        [DllImport("kernel32.dll")] static extern IntPtr LockResource(IntPtr resource);
        [DllImport("kernel32.dll", SetLastError=true)] static extern uint SizeofResource(IntPtr module, IntPtr resource);
        class Group { public string Name; public int Id; public ushort Language; }
        public static void Apply(string executable, string icon) {
            var groups = new List<Group>();
            var module = LoadLibraryEx(executable, IntPtr.Zero, 2 | 0x20);
            if (module == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
            try {
                EnumResourceNames(module, (IntPtr)14, (m,t,n,p) => {
                    int id = n.ToInt64() < 65536 ? n.ToInt32() : 0;
                    string name = id == 0 ? Marshal.PtrToStringUni(n) : null;
                    bool found = false;
                    EnumResourceLanguages(m, t, n, (mm,tt,nn,lang,pp) => { groups.Add(new Group { Id=id, Name=name, Language=lang }); found=true; return true; }, IntPtr.Zero);
                    if (!found) groups.Add(new Group { Id=id, Name=name, Language=1033 });
                    return true;
                }, IntPtr.Zero);
            } finally { FreeLibrary(module); }
            if (groups.Count == 0) groups.Add(new Group { Id=1, Language=1033 });
            var bytes = File.ReadAllBytes(icon);
            var reader = new BinaryReader(new MemoryStream(bytes));
            if (reader.ReadUInt16()!=0 || reader.ReadUInt16()!=1) throw new InvalidDataException("Invalid ICO header");
            int count = reader.ReadUInt16();
            if (count < 1 || count > 32) throw new InvalidDataException("Invalid ICO size count");
            var images = new List<byte[]>();
            var groupStream = new MemoryStream();
            var writer = new BinaryWriter(groupStream);
            writer.Write((ushort)0); writer.Write((ushort)1); writer.Write((ushort)count);
            for (int i=0; i<count; i++) {
                var entry = reader.ReadBytes(12);
                int length = BitConverter.ToInt32(entry,8);
                int offset = reader.ReadInt32();
                if (length<=0 || offset<0 || (long)offset+length>bytes.Length) throw new InvalidDataException("Invalid ICO image offset");
                var image = new byte[length]; Array.Copy(bytes,offset,image,0,length); images.Add(image);
                writer.Write(entry); writer.Write((ushort)(1200+i));
            }
            var data = groupStream.ToArray();
            var handle = BeginUpdateResource(executable,false);
            if (handle == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
            bool committed = false;
            try {
                foreach (var group in groups) {
                    for (int i=0; i<count; i++)
                        if (!UpdateResource(handle,(IntPtr)3,(IntPtr)(1200+i),group.Language,images[i],(uint)images[i].Length)) throw new Win32Exception(Marshal.GetLastWin32Error());
                    var name = group.Id != 0 ? (IntPtr)group.Id : Marshal.StringToHGlobalUni(group.Name);
                    try { if (!UpdateResource(handle,(IntPtr)14,name,group.Language,data,(uint)data.Length)) throw new Win32Exception(Marshal.GetLastWin32Error()); }
                    finally { if (group.Id==0) Marshal.FreeHGlobal(name); }
                }
                if (!EndUpdateResource(handle,false)) throw new Win32Exception(Marshal.GetLastWin32Error());
                committed = true;
            } finally { if (!committed) EndUpdateResource(handle,true); }
        }
        public static int Verify(string executable, string icon) {
            var file = File.ReadAllBytes(icon);
            var module = LoadLibraryEx(executable, IntPtr.Zero, 2 | 0x20);
            if (module == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
            try {
                int count = BitConverter.ToUInt16(file,4);
                for (int i=0; i<count; i++) {
                    int entry = 6+i*16;
                    int length = BitConverter.ToInt32(file,entry+8);
                    int offset = BitConverter.ToInt32(file,entry+12);
                    var resource = FindResource(module,(IntPtr)(1200+i),(IntPtr)3);
                    if (resource==IntPtr.Zero || SizeofResource(module,resource)!=length) throw new InvalidDataException("Missing OpenFPV executable icon size " + i);
                    var data = new byte[length];
                    Marshal.Copy(LockResource(LoadResource(module,resource)),data,0,length);
                    for (int j=0; j<length; j++) if (data[j]!=file[offset+j]) throw new InvalidDataException("Executable icon does not match source ICO");
                }
                return count;
            } finally { FreeLibrary(module); }
        }
    }
}
