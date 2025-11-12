using OxyPlot.WindowsForms;
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Data;
using System.Drawing;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;

using OxyPlot;
using OxyPlot.Series;



namespace CordicTest
{
    public partial class Form1 : Form
    {
        private PlotView plotView;

        public Form1()
        {
            InitializeComponent();

            // Create the plot view
            plotView = new PlotView
            {
                Dock = DockStyle.Fill,
                Location = new System.Drawing.Point(0, 0),
                Name = "plotView",
                Size = new System.Drawing.Size(800, 450),
                TabIndex = 0,
                Model = PlotHelper.CreatePlotModel() // Use the PlotHelper to create the plot model
            };

            // Add the plot view to the form's controls
            this.Controls.Add(plotView);
        }
    }
}
