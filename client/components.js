import {UUID, range} from './util.js';


Moon.component('output-separator', {
           template: "<hr style='display: block; height: 1px; border: 0; border-top: 1px solid #aaa; margin: 1em 0;padding: 0;'/>"
       });

Moon.component('cell-input', {
  props: ['uuid', 'input_refresh'],
  template: `<div m-html='input()'></div>`,
  methods: {
    input: function() {
      return notebook.cell[this.get('uuid')].input
    }
  }
});


Moon.component('cell-output', {
  props: ['uuid', 'output_refresh'], // style to horizontally align
  template: `<div class='labmode-output-div'>
  <div m-for='index in indices()' >
    <div m-if='display(index)' m-html='output(index)'></div>
  </div>
</div>`,
  methods: {
    indices: function() {
      return range(notebook.cell[this.get('uuid')].outputs.length)
    },
    display: function(index) {
      return notebook.cell[this.get('uuid')].display(index)
    },
    output: function(index) {
      let cell = notebook.cell[this.get('uuid')];
      cell.execute(index);
      return cell.output(index)
    }
  }
});


export const app = new Moon({
  el : "#app",
  data: {
    uuids: [],                // List of all cell uuids
    removed: [],              // uuids of deleted cells
    refresh_uuids: [],        // uuids to re-render
  },
  methods : {
    refresh:  function(uuid, type) {
      let state = this.get('refresh_uuids').includes(uuid + type) ? UUID() : false;
      notebook.refreshed(uuid, type);
      return state
    },
    prompt : function(uuid) {
      let cell = notebook.cell[uuid];
      if (cell === undefined || cell.mode=='markdown') {
        return ''
      }
      else {
        let count = (cell.prompt != null) ? cell.prompt : ' ';
        return `<br><div id='${uuid}'>In[${count}]</div>`
      }
    }
  }
})
