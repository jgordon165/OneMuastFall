// Pre-analysis setup for the flat image tools/le_unpack.py makes from
// MASTER.DAT: split the one raw block into the LE objects (code executable,
// data not), and start disassembly at the program's entry point so
// auto-analysis has somewhere to begin.
//
// Arguments: <entry> <code_end>   (hex, from re/output/image.txt)
//@category OneMuastFall
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.mem.Memory;
import ghidra.program.model.mem.MemoryBlock;

public class SetupImage extends GhidraScript {
    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length < 2) {
            printerr("usage: SetupImage <entry hex> <code end hex>");
            return;
        }
        Address entry = toAddr(Long.decode(args[0]));
        Address codeEnd = toAddr(Long.decode(args[1]));
        Memory mem = currentProgram.getMemory();
        MemoryBlock block = mem.getBlock(entry);
        if (block != null && block.contains(codeEnd)) {
            mem.split(block, codeEnd);
        }
        for (MemoryBlock b : mem.getBlocks()) {
            boolean code = b.getStart().compareTo(codeEnd) < 0;
            b.setExecute(code);
            b.setWrite(!code);
            b.setName(code ? "code" : "data");
        }
        disassemble(entry);
        createFunction(entry, "_start");
        addEntryPoint(entry);
        println("entry at " + entry + ", code ends at " + codeEnd);
    }
}
