import React from 'react';
import { LineChart, Line, BarChart, Bar, PieChart, Pie, Cell, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts';

const Dashboard: React.FC = () => {
  const weeklyAttendanceData = [
    { day: 'Mon', value: 45 },
    { day: 'Tue', value: 48 },
    { day: 'Wed', value: 42 },
    { day: 'Thu', value: 47 },
    { day: 'Fri', value: 44 },
    { day: 'Sat', value: 38 },
    { day: 'Today', value: 47 }
  ];

  const taskDistribution = [
    { name: 'Completed', value: 42 },
    { name: 'In Progress', value: 33 },
    { name: 'Pending', value: 25 }
  ];

  const COLORS = ['#22c55e', '#ff8c42', '#d1d5db'];

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Header */}
      <div className="bg-white border-b border-gray-200 px-8 py-6">
        <h1 className="text-3xl font-bold text-gray-900">Project Dashboard</h1>
        <p className="text-gray-600 mt-1">Monday, 12 May 2025 — Real-time site overview</p>
      </div>

      {/* Main Content */}
      <div className="p-8">
        {/* KPI Cards */}
        <div className="grid grid-cols-4 gap-6 mb-8">
          <div className="bg-white rounded-lg shadow p-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-gray-600 text-sm">Workers On Site</p>
                <p className="text-3xl font-bold text-gray-900 mt-2">47/151</p>
                <p className="text-gray-600 text-xs mt-2">4 absent • 2 late</p>
              </div>
              <div className="text-3xl text-blue-500">👥</div>
            </div>
          </div>

          <div className="bg-white rounded-lg shadow p-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-gray-600 text-sm">Active Tasks</p>
                <p className="text-3xl font-bold text-gray-900 mt-2">6</p>
                <p className="text-gray-600 text-xs mt-2">2 completed today</p>
              </div>
              <div className="text-3xl text-orange-500">📋</div>
            </div>
          </div>

          <div className="bg-white rounded-lg shadow p-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-gray-600 text-sm">Overall Productivity</p>
                <p className="text-3xl font-bold text-gray-900 mt-2">76%</p>
                <p className="text-gray-600 text-xs mt-2">+4% from last week</p>
              </div>
              <div className="text-3xl text-green-500">📈</div>
            </div>
          </div>

          <div className="bg-white rounded-lg shadow p-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-gray-600 text-sm">Alerts</p>
                <p className="text-3xl font-bold text-gray-900 mt-2">3</p>
                <p className="text-gray-600 text-xs mt-2">2 attendant • 1 safety</p>
              </div>
              <div className="text-3xl text-red-500">⚠️</div>
            </div>
          </div>
        </div>

        {/* Charts */}
        <div className="grid grid-cols-3 gap-6">
          {/* Weekly Attendance */}
          <div className="col-span-2 bg-white rounded-lg shadow p-6">
            <h2 className="text-lg font-bold text-gray-900 mb-4">Weekly Attendance</h2>
            <p className="text-gray-600 text-sm mb-4">All projects combined</p>
            <ResponsiveContainer width="100%" height={300}>
              <BarChart data={weeklyAttendanceData}>
                <CartesianGrid strokeDasharray="3 3" />
                <XAxis dataKey="day" />
                <YAxis />
                <Tooltip />
                <Bar dataKey="value" fill="#ff8c42" />
              </BarChart>
            </ResponsiveContainer>
          </div>

          {/* Task Distribution */}
          <div className="bg-white rounded-lg shadow p-6">
            <h2 className="text-lg font-bold text-gray-900 mb-4">Task Distribution</h2>
            <p className="text-gray-600 text-sm mb-4">All active projects</p>
            <ResponsiveContainer width="100%" height={300}>
              <PieChart>
                <Pie data={taskDistribution} cx="50%" cy="50%" innerRadius={60} outerRadius={100} paddingAngle={2} dataKey="value">
                  {taskDistribution.map((entry, index) => (
                    <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
                  ))}
                </Pie>
              </PieChart>
            </ResponsiveContainer>
            <div className="mt-4 space-y-2 text-sm">
              <div className="flex items-center gap-2">
                <div className="w-3 h-3 rounded-full bg-green-500"></div>
                <span>Completed</span>
              </div>
              <div className="flex items-center gap-2">
                <div className="w-3 h-3 rounded-full bg-orange-500"></div>
                <span>In Progress</span>
              </div>
              <div className="flex items-center gap-2">
                <div className="w-3 h-3 rounded-full bg-gray-300"></div>
                <span>Pending</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default Dashboard;