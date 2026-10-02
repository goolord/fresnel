// A hidden file input: the function it returns opens the file dialog, and onFile gets the
// file picked there (makeMultiple: onFiles gets any number of them).

open! Web

let picker = (parent, ~accept, ~multiple, onFiles) => {
  let input = el("input", ~parent)
  input->setInputType("file")
  input->setMultiple(multiple)
  input->setAccept(accept)
  input->setStyle("display", "none")
  input->onEvent(#change, _ => {
    input->files->Option.forEach(list => onFiles(filesToArray(list)))
    input->setValue("")
  })
  () => input->click
}

let make = (parent, ~accept, onFile) =>
  picker(parent, ~accept, ~multiple=false, files => files[0]->Option.forEach(onFile))

let makeMultiple = (parent, ~accept, onFiles) => picker(parent, ~accept, ~multiple=true, onFiles)
